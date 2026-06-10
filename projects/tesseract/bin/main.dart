import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ds_shelf/ds_shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

// In-memory game state
final Map<String, bool> gameFeatureFlags = {
  'enableWaxisRotation': true,
  'showTargetReference': true,
  'hypercolorMode': false,
  'hardcoreDifficulty': false,
};

int highscore = 1200; // in seconds, lower is better (time attack)

// Stream controller to broadcast game event telemetries
final StreamController<String> gameTelemetryBroadcast = StreamController<String>.broadcast();

void main() async {
  print('🎮 Starting Tesseract 4D Game Server...');

  final server = DSShelfCore();

  // Add standard middlewares
  server.addMiddleware(dsShelfCorsMiddleware());
  server.addMiddleware(dsShelfBodyParserMiddleware());

  // 1. API - Status Endpoint
  server.addGetRoute('/api/status', (Request request) {
    return Response.ok(
      jsonEncode({
        'status': 'active',
        'engine': 'DartStream Standard Engine',
        'subsystem': 'Tesseract 4D Core',
        'uptime': ProcessInfo.currentRss,
        'highscore': highscore,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // 2. API - Feature Flags
  server.addGetRoute('/api/features', (Request request) {
    return Response.ok(
      jsonEncode(gameFeatureFlags),
      headers: {'Content-Type': 'application/json'},
    );
  });

  server.addPostRoute('/api/features', (Request request) async {
    final parsedBody = request.context['ds_shelf.body'];
    if (parsedBody is Map) {
      parsedBody.forEach((key, value) {
        if (gameFeatureFlags.containsKey(key) && value is bool) {
          gameFeatureFlags[key] = value;
          print('🎮 Game Feature Flag updated: $key = $value');
        }
      });
      // Broadcast flag update to all game clients
      gameTelemetryBroadcast.add(jsonEncode({
        'type': 'flag_update',
        'flags': gameFeatureFlags,
        'timestamp': DateTime.now().toIso8601String(),
      }));
      return Response.ok(
        jsonEncode({'status': 'success', 'features': gameFeatureFlags}),
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

      if (type == 'level_win' && score < highscore) {
        highscore = score;
        payload['new_highscore'] = true;
      }

      // Broadcast this telemetry event to SSE listeners
      gameTelemetryBroadcast.add(jsonEncode(payload));
      print('📈 Telemetry received: type=$type, level=$level, message=$message');

      return Response.ok(
        jsonEncode({'status': 'success', 'highscore': highscore}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.badRequest(
      body: jsonEncode({'error': 'Invalid request body'}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // 4. API - AI Assistant / 4D Game Master
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
      reply = 'Focus on aligning the inner W-depth cubes first. Try adjusting the XW and YW sliders to align the inner-outer spacing, and then use XY and YZ to match the rotation angle. Toggling "showTargetReference" off will hide the target, if you want a extreme mathematical challenge!';
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
  server.addGetRoute('/api/stream', (Request request) {
    print('🔌 New game client connected to SSE telemetry channel.');
    
    final controller = StreamController<List<int>>();
    
    // Broadcast initial state
    final welcome = jsonEncode({
      'type': 'welcome',
      'message': 'Connected to Tesseract Game Engine Broadcast.',
      'highscore': highscore,
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

  // 7. Start Server Listener
  final handler = server.handler;
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  await shelf_io.serve(handler, 'localhost', port);

  print('\n✅ Tesseract 4D Server running at http://localhost:8080');
}
