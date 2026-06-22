import 'dart:io';
import 'package:test/test.dart';
import 'package:dartstream_client/dartstream_client.dart';

void main() {
  group('DartStream SaaS Live Smoke Probe', () {
    final email = Platform.environment['DARTSTREAM_EMAIL'];
    final password = Platform.environment['DARTSTREAM_PASSWORD'];
    final firebaseApiKey = Platform.environment['DARTSTREAM_FIREBASE_API_KEY'];

    final hasCredentials = email != null && email.isNotEmpty &&
        password != null && password.isNotEmpty &&
        firebaseApiKey != null && firebaseApiKey.isNotEmpty;

    test(
      'can authenticate and connect to SaaS dev-api',
      () async {
        final saasClient = DartStreamClient(
          config: DartStreamConfig.dev(firebaseApiKey: firebaseApiKey!),
        );

        print('📡 Onboarding session for: $email');
        final firebaseSession = await saasClient.createEmailPasswordSession(
          email: email!,
          password: password!,
        );
        final session = await saasClient.onboardFirebaseSession(firebaseSession);

        expect(session.userId, isNotEmpty);
        expect(session.idToken, isNotEmpty);
        print('🔐 Onboarded successfully. User ID: ${session.userId}');

        print('📡 Testing feature flag fetch...');
        final result = await saasClient.featureFlag(
          session,
          'enableWaxisRotation',
          fallback: true,
        );
        expect(result, isA<bool>());
        print('✅ Feature flag enableWaxisRotation: $result');
      },
      skip: hasCredentials ? false : 'Set DARTSTREAM_EMAIL, DARTSTREAM_PASSWORD, and DARTSTREAM_FIREBASE_API_KEY to run live smoke test',
    );
  });
}
