import 'dart:convert';
import 'package:dartstream_client/dartstream_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../lib/state/session.dart';
import '../lib/config.dart';

void main() {
  group('Session Authentication Tests via MockClient', () {
    test('Successful signUp flow (Firebase -> DartStream signup 201)', () async {
      final session = Session();
      final mockClient = MockClient((request) async {
        // 1. Firebase Auth Signup request
        if (request.url.toString().contains('accounts:signUp')) {
          return http.Response(
            jsonEncode({
              'idToken': 'mock-id-token',
              'refreshToken': 'mock-refresh-token',
              'email': 'new-user@example.com',
              'localId': 'mock-local-id',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        // 2. DartStream Auth Signup request
        if (request.url.path == '/api/v1/auth/signup') {
          return http.Response(
            jsonEncode({
              'user': {
                'id': 'ds-user-123',
                'active_tenant_id': 'ds-tenant-456',
              }
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('Not Found', 404);
      });

      await session.signUp(
        'new-user@example.com',
        'password123',
        httpClient: mockClient,
      );

      expect(session.status, equals(SessionStatus.signedIn));
      expect(session.isSignedIn, isTrue);
      expect(session.userId, equals('ds-user-123'));
      expect(session.tenantId, equals('ds-tenant-456'));
      expect(session.email, equals('new-user@example.com'));
      expect(session.errorMessage, null);
    });

    test('signUp flow handles 409 Conflict by calling login instead', () async {
      final session = Session();
      var signupCalled = false;
      var loginCalled = false;

      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('accounts:signUp')) {
          return http.Response(
            jsonEncode({
              'idToken': 'mock-id-token',
              'refreshToken': 'mock-refresh-token',
              'email': 'existing-user@example.com',
              'localId': 'mock-local-id',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.path == '/api/v1/auth/signup') {
          signupCalled = true;
          return http.Response(
            jsonEncode({'error': 'User already exists'}),
            409,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.path == '/api/v1/auth/login') {
          loginCalled = true;
          return http.Response(
            jsonEncode({
              'user': {
                'id': 'ds-user-123',
                'active_tenant_id': 'ds-tenant-456',
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('Not Found', 404);
      });

      await session.signUp(
        'existing-user@example.com',
        'password123',
        httpClient: mockClient,
      );

      expect(signupCalled, isTrue);
      expect(loginCalled, isTrue);
      expect(session.status, equals(SessionStatus.signedIn));
      expect(session.userId, equals('ds-user-123'));
      expect(session.tenantId, equals('ds-tenant-456'));
    });

    test('Successful signIn flow (Firebase -> DartStream signup/login)', () async {
      final session = Session();
      final mockClient = MockClient((request) async {
        // 1. Firebase Auth Signin request
        if (request.url.toString().contains('accounts:signInWithPassword')) {
          return http.Response(
            jsonEncode({
              'idToken': 'mock-id-token',
              'refreshToken': 'mock-refresh-token',
              'email': 'user@example.com',
              'localId': 'mock-local-id',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        // 2. DartStream Auth Signup/login request
        if (request.url.path == '/api/v1/auth/signup') {
          return http.Response(
            jsonEncode({
              'user': {
                'id': 'ds-user-123',
                'active_tenant_id': 'ds-tenant-456',
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('Not Found', 404);
      });

      await session.signIn(
        'user@example.com',
        'password123',
        httpClient: mockClient,
      );

      expect(session.status, equals(SessionStatus.signedIn));
      expect(session.userId, equals('ds-user-123'));
      expect(session.tenantId, equals('ds-tenant-456'));
    });

    test('Surfaces Firebase authentication failures to UI', () async {
      final session = Session();
      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('accounts:signInWithPassword')) {
          return http.Response(
            jsonEncode({
              'error': {
                'message': 'INVALID_PASSWORD',
                'code': 400,
              }
            }),
            400,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      await session.signIn(
        'user@example.com',
        'wrongpassword',
        httpClient: mockClient,
      );

      expect(session.status, equals(SessionStatus.error));
      expect(session.errorMessage, contains('The email or password is incorrect.'));
      expect(session.connection, isNull);
    });

    test('Surfaces DartStream API errors (like 401 Unauthorized) to UI', () async {
      final session = Session();
      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('accounts:signInWithPassword')) {
          return http.Response(
            jsonEncode({
              'idToken': 'mock-id-token',
              'refreshToken': 'mock-refresh-token',
              'email': 'user@example.com',
              'localId': 'mock-local-id',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.path == '/api/v1/auth/signup') {
          return http.Response(
            'Unauthorized Project Config',
            401,
            headers: {'content-type': 'text/plain'},
          );
        }

        return http.Response('Not Found', 404);
      });

      await session.signIn(
        'user@example.com',
        'password123',
        httpClient: mockClient,
      );

      expect(session.status, equals(SessionStatus.error));
      expect(session.errorMessage, contains('HTTP 401: Unauthorized Project Config'));
      expect(session.connection, isNull);
    });

    test('Successful signInWithProvider flow (Google)', () async {
      final session = Session();
      final mockClient = MockClient((request) async {
        // 1. Firebase Auth Signin/Signup request
        if (request.url.toString().contains('accounts:signInWithPassword')) {
          return http.Response(
            jsonEncode({
              'idToken': 'mock-id-token',
              'refreshToken': 'mock-refresh-token',
              'email': 'alex.dev@gmail.com',
              'localId': 'mock-local-id',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        // 2. Onboard Firebase Token
        if (request.url.path == '/api/v1/auth/signup') {
          return http.Response(
            jsonEncode({
              'user': {
                'id': 'ds-user-123',
                'active_tenant_id': 'ds-tenant-456',
              }
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }

        // 3. Onboard Provider (Google) Token
        if (request.url.path == '/api/v1/auth/signin/google') {
          return http.Response(
            jsonEncode({
              'user': {
                'id': 'ds-user-123',
                'active_tenant_id': 'ds-tenant-456-google',
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('Not Found', 404);
      });

      await session.signInWithProvider(
        DartStreamAuthProvider.google,
        'alex.dev@gmail.com',
        httpClient: mockClient,
      );

      expect(session.status, equals(SessionStatus.signedIn));
      expect(session.userId, equals('ds-user-123'));
      expect(session.tenantId, equals('ds-tenant-456-google'));
    });
  });
}
