import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:tesseract/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Tesseract Server API tests', () {
    late Handler handler;

    setUp(() {
      // Create a server instance with failFast disabled to allow local test execution with fallback session
      final server = createServer(failFast: false);
      handler = server.handler;
    });

    test('GET /api/status returns 200 and active status info', () async {
      final request = Request('GET', Uri.parse('http://localhost/api/status'));
      final response = await handler(request);
      expect(response.statusCode, equals(200));
      expect(response.headers['Content-Type'], contains('application/json'));
      
      final body = jsonDecode(await response.readAsString());
      expect(body['status'], equals('active'));
      expect(body['engine'], equals('DartStream Standard Engine'));
      expect(body['highscore'], equals(1200));
      expect(body['saas_client']['initialized'], isFalse); // False in fallback mode during local tests
      expect(body['saas_client']['saas_session'], equals('fallback'));
      expect(body['saas_client']['target'], contains('dartstream.io'));
    });

    test('GET /api/features returns default feature flags', () async {
      final request = Request('GET', Uri.parse('http://localhost/api/features'));
      final response = await handler(request);
      expect(response.statusCode, equals(200));
      
      final body = jsonDecode(await response.readAsString());
      expect(body['enableWaxisRotation'], isTrue);
      expect(body['showTargetReference'], isTrue);
      expect(body['hypercolorMode'], isFalse);
    });

    test('POST /api/features updates feature flags', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/api/features'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'hypercolorMode': true, 'hardcoreDifficulty': true}),
      );
      final response = await handler(request);
      expect(response.statusCode, equals(200));
      
      final body = jsonDecode(await response.readAsString());
      expect(body['status'], equals('success'));
      expect(body['features']['hypercolorMode'], isTrue);
      expect(body['features']['hardcoreDifficulty'], isTrue);
    });

    test('POST /api/chat handles user message queries', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': 'what is a tesseract?'}),
      );
      final response = await handler(request);
      expect(response.statusCode, equals(200));
      
      final body = jsonDecode(await response.readAsString());
      expect(body['reply'], contains('4-dimensional hypercube'));
    });
  });

  group('Tesseract Server SaaS Integration tests (MockClient)', () {
    test('Server establishes session via M2M Client Credentials and fetches feature flags successfully', () async {
      var tokenRequestCount = 0;
      var flagRequestCount = 0;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/oauth/token') {
          tokenRequestCount++;
          // Verify form-urlencoded body
          expect(request.headers['content-type'], contains('application/x-www-form-urlencoded'));
          expect(request.body, contains('grant_type=client_credentials'));
          expect(request.body, contains('client_id=test-id'));
          expect(request.body, contains('client_secret=test-secret'));
          
          return http.Response(
            jsonEncode({
              'access_token': 'test-m2m-access-token',
              'token_type': 'Bearer',
              'expires_in': 3600,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        
        if (request.url.path == '/api/v1/platform/feature-flags/enableWaxisRotation') {
          flagRequestCount++;
          // Verify auth header contains the Bearer token we returned
          expect(request.headers['authorization'], equals('Bearer test-m2m-access-token'));
          expect(request.headers['x-tenant-id'], equals('m2m-tenant'));
          
          return http.Response(
            jsonEncode({
              'key': 'enableWaxisRotation',
              'enabled': true,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        
        // Return 200 for other flags to prevent error logs
        return http.Response(jsonEncode({'enabled': false}), 200, headers: {'content-type': 'application/json'});
      });

      // Initialize server with MockClient and custom environment variables
      final server = createServer(
        failFast: false,
        httpClient: mockClient,
        environment: {
          'DARTSTREAM_CLIENT_ID': 'test-id',
          'DARTSTREAM_CLIENT_SECRET': 'test-secret',
        },
      );

      final handler = server.handler;

      // Trigger the status API (which awaits the ensureLoaded() future)
      final request = Request('GET', Uri.parse('http://localhost/api/status'));
      final response = await handler(request);

      expect(response.statusCode, equals(200));
      expect(tokenRequestCount, equals(1));
      expect(flagRequestCount, equals(1));

      final body = jsonDecode(await response.readAsString());
      expect(body['saas_client']['saas_session'], equals('live'));
      expect(body['highscore'], equals(1200));
    });

    test('Server handles 401 and successfully re-authenticates and retries action', () async {
      var tokenRequestCount = 0;
      var flagRequestCount = 0;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/oauth/token') {
          tokenRequestCount++;
          return http.Response(
            jsonEncode({
              'access_token': 'fresh-token-$tokenRequestCount',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.path.contains('/api/v1/platform/feature-flags/')) {
          flagRequestCount++;
          if (flagRequestCount == 1) {
            // First flag request returns 401 unauthorized to trigger re-auth
            return http.Response(
              jsonEncode({'error': 'Unauthorized token expired'}),
              401,
              headers: {'content-type': 'application/json'},
            );
          }
          // Subsequent requests succeed using the fresh token
          expect(request.headers['authorization'], equals('Bearer fresh-token-2'));
          return http.Response(
            jsonEncode({'enabled': true}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('Not Found', 404);
      });

      final server = createServer(
        failFast: false,
        httpClient: mockClient,
        environment: {
          'DARTSTREAM_CLIENT_ID': 'test-id',
          'DARTSTREAM_CLIENT_SECRET': 'test-secret',
        },
      );

      final handler = server.handler;

      // Trigger GET status which starts loadFeatureFlags/experience loads
      final request = Request('GET', Uri.parse('http://localhost/api/status'));
      final response = await handler(request);

      expect(response.statusCode, equals(200));
      // Handled 401 by requesting token twice: initial and re-auth
      expect(tokenRequestCount, equals(2));
    });
  });
}
