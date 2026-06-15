import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ds_shelf/ds_shelf.dart' hide DSShelfCore;
import 'package:dartstream_client/dartstream_client.dart';

// In-memory default configurations
final Map<String, bool> defaultFeatureFlags = {
  'enableWaxisRotation': true,
  'showTargetReference': true,
  'hypercolorMode': false,
  'hardcoreDifficulty': false,
};

const int defaultHighscore = 1200;

/// Custom DSShelfCore that supports POST and static file routing,
/// bypassing the limitations of the published ds_shelf 0.0.1 package.
class DSShelfCore {
  final List<Middleware> _middlewares = [];
  final Router _router = Router();

  DSShelfCore() {
    addMiddleware(logRequests());
    _router.get('/health', (Request request) {
      return Response.ok('OK');
    });
  }

  void addMiddleware(Middleware middleware) {
    _middlewares.add(middleware);
  }

  void addGetRoute(String path, Function handler) {
    _router.get(path, handler);
  }

  void addPostRoute(String path, Function handler) {
    _router.post(path, handler);
  }

  void addStaticRoute(String staticPath) {
    _router.all('/<ignored|.*>', createStaticHandler(staticPath, defaultDocument: 'index.html'));
  }

  Handler get handler {
    var pipeline = Pipeline();
    for (final mw in _middlewares) {
      pipeline = pipeline.addMiddleware(mw);
    }
    return pipeline.addHandler(_router);
  }
}

/// Custom JSON body parser middleware since it's not present in the published ds_shelf 0.0.1.
Middleware dsShelfBodyParserMiddleware() {
  return (Handler inner) {
    return (Request request) async {
      if ((request.method == 'POST' || request.method == 'PUT' || request.method == 'PATCH') &&
          request.headers['content-type']?.contains('application/json') == true) {
        try {
          final bodyBytes = await request.read().toList();
          final bodyStr = utf8.decode(bodyBytes.expand((x) => x).toList());
          final parsed = bodyStr.isNotEmpty ? jsonDecode(bodyStr) : null;
          
          final newRequest = request.change(
            context: {
              ...request.context,
              'ds_shelf.body': parsed,
            },
            body: bodyStr,
          );
          return await inner(newRequest);
        } catch (e) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Malformed JSON body'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }
      return await inner(request);
    };
  };
}

DSShelfCore createServer({bool failFast = true}) {
  final server = DSShelfCore();

  // Add standard middlewares
  server.addMiddleware(dsShelfCorsMiddleware());
  server.addMiddleware(dsShelfBodyParserMiddleware());

  // Initialize DartStream SaaS client using credentials from environment
  final email = Platform.environment['DARTSTREAM_EMAIL'];
  final password = Platform.environment['DARTSTREAM_PASSWORD'];
  final firebaseApiKey = Platform.environment['DARTSTREAM_FIREBASE_API_KEY'];

  if (failFast) {
    if (email == null || email.isEmpty) {
      throw StateError('DARTSTREAM_EMAIL environment variable is required.');
    }
    if (password == null || password.isEmpty) {
      throw StateError('DARTSTREAM_PASSWORD environment variable is required.');
    }
    if (firebaseApiKey == null || firebaseApiKey.isEmpty) {
      throw StateError('DARTSTREAM_FIREBASE_API_KEY environment variable is required.');
    }
  }

  final saasClient = DartStreamClient(
    config: DartStreamConfig.dev(firebaseApiKey: firebaseApiKey),
  );
  print('📡 DartStream SaaS Client initialized (Dev Environment).');

  // Session onboarding for SaaS APIs
  DartStreamSession? saasSession;
  String saasSessionState = 'none';

  Future<void> onboardSession() async {
    saasSessionState = 'initializing';
    try {
      final firebaseSession = await saasClient.createEmailPasswordSession(
        email: email!,
        password: password!,
      );
      saasSession = await saasClient.onboardFirebaseSession(firebaseSession);
      saasSessionState = 'live';
      print('🔐 SaaS session onboarded successfully for user: ${saasSession?.userId}');
    } catch (e) {
      print('Warning: Failed to onboard SaaS session: $e.');
      if (failFast) {
        throw StateError('Failed to onboard SaaS session: $e');
      }
      print('Using local fallback session.');
      saasSessionState = 'fallback';
      saasSession = DartStreamSession(
        idToken: 'fallback-token',
        userId: 'dev-user',
        tenantId: 'dev-tenant',
        raw: {},
      );
    }
  }

  final sessionFuture = Future(() async {
    if (!failFast && (email == null || password == null || firebaseApiKey == null)) {
      saasSessionState = 'fallback';
      saasSession = DartStreamSession(
        idToken: 'fallback-token',
        userId: 'dev-user',
        tenantId: 'dev-tenant',
        raw: {},
      );
      return;
    }
    await onboardSession();
  });

  Future<DartStreamSession> ensureSession() async {
    await sessionFuture;
    return saasSession!;
  }

  // Helper function to run SaaS actions with automatic retry on 401
  Future<T> runWithRetry<T>(Future<T> Function(DartStreamSession session) action) async {
    var session = await ensureSession();
    try {
      return await action(session);
    } on DartStreamApiException catch (e) {
      if (e.statusCode == 401 && saasSessionState != 'fallback') {
        print('📡 SaaS call unauthorized (401). Attempting to re-authenticate...');
        await onboardSession();
        session = saasSession!;
        return await action(session);
      }
      rethrow;
    }
  }

  // Features and stats state
  final flags = Map<String, bool>.from(defaultFeatureFlags);
  int highscoreVal = defaultHighscore;

  bool isLoaded = false;
  final loadFuture = Future(() async {
    // 1. Try loading feature flags from ds-platform
    try {
      final enableWaxis = await runWithRetry((s) => saasClient.featureFlag(s, 'enableWaxisRotation', fallback: true));
      final showTarget = await runWithRetry((s) => saasClient.featureFlag(s, 'showTargetReference', fallback: true));
      final hypercolor = await runWithRetry((s) => saasClient.featureFlag(s, 'hypercolorMode', fallback: false));
      final hardcore = await runWithRetry((s) => saasClient.featureFlag(s, 'hardcoreDifficulty', fallback: false));
      
      flags['enableWaxisRotation'] = enableWaxis;
      flags['showTargetReference'] = showTarget;
      flags['hypercolorMode'] = hypercolor;
      flags['hardcoreDifficulty'] = hardcore;
      print('🎮 Feature flags loaded from SaaS platform.');
    } catch (e) {
      print('Error loading flags from SaaS: $e. Using in-memory defaults.');
    }

    // 2. Try loading highscore from ds-experience cloud-save
    try {
      final cloudData = await runWithRetry((s) => saasClient.experience.loadCloudSave(s, slotKey: 'highscore'));
      if (cloudData != null && cloudData.containsKey('highscore')) {
        highscoreVal = cloudData['highscore'] as int;
        print('🏆 Highscore loaded from SaaS cloud-save: $highscoreVal');
      }
    } catch (e) {
      print('Error loading highscore from SaaS: $e. Using in-memory defaults.');
    }
    
    isLoaded = true;
  });

  Future<void> ensureLoaded() async {
    if (!isLoaded) {
      await loadFuture;
    }
  }

  // Stream controller to broadcast game event telemetries
  final StreamController<String> gameTelemetryBroadcast = StreamController<String>.broadcast();

  // 1. API - Status Endpoint
  server.addGetRoute('/api/status', (Request request) async {
    await ensureLoaded();
    return Response.ok(
      jsonEncode({
        'status': 'active',
        'engine': 'DartStream Standard Engine',
        'subsystem': 'Tesseract 4D Core',
        'uptime': ProcessInfo.currentRss,
        'highscore': highscoreVal,
        'saas_client': {
          'initialized': saasSessionState == 'live',
          'target': saasClient.config.authBaseUrl.toString(),
          'saas_session': saasSessionState,
        }
      }),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // 2. API - Feature Flags
  server.addGetRoute('/api/features', (Request request) async {
    await ensureLoaded();
    return Response.ok(
      jsonEncode(flags),
      headers: {'Content-Type': 'application/json'},
    );
  });

  server.addPostRoute('/api/features', (Request request) async {
    await ensureLoaded();
    final parsedBody = request.context['ds_shelf.body'];
    if (parsedBody is Map) {
      for (final entry in parsedBody.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && flags.containsKey(key) && value is bool) {
          flags[key] = value;
          print('🎮 Game Feature Flag updated in-memory: $key = $value');
          
          try {
            await runWithRetry((s) async {
              try {
                await saasClient.platform.updateFeatureFlag(s, key, updates: {'enabled': value});
              } on DartStreamApiException catch (e) {
                if (e.statusCode == 404) {
                  print('SaaS: Feature flag $key does not exist. Creating it...');
                  await saasClient.platform.createFeatureFlag(s, flag: {
                    'key': key,
                    'enabled': value,
                  });
                } else {
                  rethrow;
                }
              }
            });
            print('SaaS: Updated/Created feature flag $key = $value');
          } catch (e) {
            print('Error updating feature flag $key on SaaS: $e');
          }
        }
      }

      // Broadcast flag update to all game clients
      gameTelemetryBroadcast.add(jsonEncode({
        'type': 'flag_update',
        'flags': flags,
        'timestamp': DateTime.now().toIso8601String(),
      }));
      return Response.ok(
        jsonEncode({'status': 'success', 'features': flags}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.badRequest(
      body: jsonEncode({'error': 'Invalid request body'}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // 3. API - Submit Game Telemetry (Rotations, Scores, Completion)
  server.addPostRoute('/api/game/telemetry', (Request request) async {
    await ensureLoaded();
    final parsedBody = request.context['ds_shelf.body'];
    if (parsedBody is Map) {
      final type = parsedBody['type']?.toString() ?? 'unknown';
      final rotations = parsedBody['rotations'] ?? 0;
      final score = parsedBody['score'] ?? 0;
      final level = parsedBody['level'] ?? 1;
      final message = parsedBody['message']?.toString() ?? '';

      // Create event payload
      final payload = {
        'type': type,
        'rotations': rotations,
        'score': score,
        'level': level,
        'message': message,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Send telemetry event to ds-reactive SaaS
      try {
        await runWithRetry((s) => saasClient.reactive.trackEvent(s, eventType: type, payload: payload));
        print('SaaS: Telemetry event tracked: $type');
      } catch (e) {
        print('Error tracking telemetry event to SaaS: $e');
      }

      if (type == 'level_win' && score < highscoreVal) {
        highscoreVal = score;
        payload['new_highscore'] = true;

        // Save new highscore to ds-experience SaaS cloud-save
        try {
          await runWithRetry((s) => saasClient.experience.saveCloudSave(
            s,
            slotKey: 'highscore',
            payload: {'highscore': highscoreVal},
          ));
          print('SaaS: Saved new highscore to cloud-save: $highscoreVal');
        } catch (e) {
          print('Error saving highscore to SaaS cloud-save: $e');
        }
      }

      // Broadcast this telemetry event to SSE listeners
      gameTelemetryBroadcast.add(jsonEncode(payload));
      print('📈 Telemetry received: type=$type, level=$level, message=$message');

      return Response.ok(
        jsonEncode({'status': 'success', 'highscore': highscoreVal}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.badRequest(
      body: jsonEncode({'error': 'Invalid request body'}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // 4. API - AI / Scripted Game Master Assistant
  server.addPostRoute('/api/chat', (Request request) async {
    final parsedBody = request.context['ds_shelf.body'];
    String userMessage = '';
    if (parsedBody is Map && parsedBody.containsKey('message')) {
      userMessage = parsedBody['message']?.toString() ?? '';
    }

    String reply = '';
    final msgLower = userMessage.toLowerCase();
    
    if (msgLower.contains('tesseract') || msgLower.contains('4d') || msgLower.contains('dimension')) {
      reply = 'A Tesseract is a 4-dimensional hypercube. It has 16 vertices, 32 edges, 24 square faces, and 8 cubic cells. Since we cannot see 4D, we project it into 3D using perspective projection, and then project that 3D shape onto your 2D screen. In this game, rotating along the XW, YW, and ZW planes rotates the tesseract inside the 4th dimension (W-axis), folding it inside-out!';
    } else if (msgLower.contains('how to play') || msgLower.contains('rules') || msgLower.contains('solve')) {
      reply = 'Objective: Rotate the larger central tesseract until its 4D rotation matches the smaller target reference on the right. Use the sliders to rotate along 4D planes: XY/XZ/YZ (standard 3D rotations) and XW/YW/ZW (4D rotations along the W-axis). When the shapes align within threshold, the lock will break, and you clear the level!';
    } else if (msgLower.contains('hint') || msgLower.contains('help')) {
      reply = 'Focus on aligning the inner W-depth cubes first. Try adjusting the XW and YW sliders to align the inner-outer spacing, and then use XY and YZ to match the rotation angle. Toggling "showTargetReference" off will hide the target, if you want an extreme mathematical challenge!';
    } else {
      reply = 'Welcome to Tesseract 4D. I am monitoring your rotations. Level metrics are being streamed over DartStream SSE. Use "help" for controls, or ask "what is a tesseract" to learn more!';
    }

    return Response.ok(
      jsonEncode({
        'reply': reply,
        'timestamp': DateTime.now().toIso8601String(),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // 5. API - Server-Sent Events (SSE) Live Feed
  server.addGetRoute('/api/stream', (Request request) async {
    await ensureLoaded();
    print('🔌 New game client connected to SSE telemetry channel.');
    
    final controller = StreamController<List<int>>();
    
    // Broadcast initial state
    final welcome = jsonEncode({
      'type': 'welcome',
      'message': 'Connected to Tesseract Game Engine Broadcast.',
      'highscore': highscoreVal,
      'timestamp': DateTime.now().toIso8601String(),
    });
    controller.add(utf8.encode('data: $welcome\n\n'));

    // Subscribe to backend event broadcaster
    final subscription = gameTelemetryBroadcast.stream.listen((event) {
      if (!controller.isClosed) {
        controller.add(utf8.encode('data: $event\n\n'));
      }
    });

    // Send periodic engine status to keep connection alive
    final keepAliveTimer = Timer.periodic(Duration(seconds: 4), (t) {
      if (!controller.isClosed) {
        final status = jsonEncode({
          'type': 'keep_alive',
          'message': 'Engine ticking normally.',
          'timestamp': DateTime.now().toIso8601String(),
        });
        controller.add(utf8.encode('data: $status\n\n'));
      }
    });

    controller.onCancel = () {
      print('❌ Game client disconnected from SSE telemetry.');
      subscription.cancel();
      keepAliveTimer.cancel();
      controller.close();
    };

    return Response.ok(
      controller.stream,
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Access-Control-Allow-Origin': '*',
      },
    );
  });

  // 6. Static Files Serving
  String? staticPath;
  if (Directory('web').existsSync()) {
    staticPath = 'web';
  } else if (Directory('projects/tesseract/web').existsSync()) {
    staticPath = 'projects/tesseract/web';
  }

  if (staticPath != null) {
    server.addStaticRoute(staticPath);
    print('📁 Game assets served from: $staticPath');
  } else {
    print('⚠️ Warning: web directory not found. Static serving disabled.');
  }

  return server;
}
