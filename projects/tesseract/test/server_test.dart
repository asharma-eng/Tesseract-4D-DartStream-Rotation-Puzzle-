import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:tesseract/main.dart';

void main() {
  group('Tesseract Server API tests', () {
    late Handler handler;

    setUp(() {
      // Create a server instance (falling back to in-memory state since storageManager is null)
      final server = createServer();
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
      expect(body['saas_client']['initialized'], isTrue);
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
}
