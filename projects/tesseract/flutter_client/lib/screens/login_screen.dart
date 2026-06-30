import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

import '../config.dart';
import '../state/session.dart';

enum AuthMode { signUp, signIn }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});
  final Session session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  AuthMode _mode = AuthMode.signUp;
  String? _localError;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _isSignUp => _mode == AuthMode.signUp;

  void _setMode(AuthMode mode) {
    setState(() {
      _mode = mode;
      _localError = null;
    });
  }

  String? _validate() {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      return 'Enter a valid email address.';
    }
    if (_password.text.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    if (_isSignUp && _password.text != _confirm.text) {
      return 'Passwords do not match.';
    }
    return null;
  }

  void _submit() {
    final error = _validate();
    if (error != null) {
      setState(() => _localError = error);
      return;
    }
    setState(() => _localError = null);
    final email = _email.text.trim();
    final password = _password.text;
    if (_isSignUp) {
      widget.session.signUp(email, password);
    } else {
      widget.session.signIn(email, password);
    }
  }

  InputDecoration _customInputDecoration({
    required String labelText,
    required String hintText,
    required IconData prefixIcon,
    Widget? suffixIcon,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
      helperStyle: const TextStyle(color: Colors.white38, fontSize: 11),
      labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
      hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
      prefixIcon: Icon(prefixIcon, color: const Color(0xFF00F0FF), size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.black.withOpacity(0.3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF00F0FF), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF0055), width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF0055), width: 2),
      ),
    );
  }

  Widget _buildActionButton({
    required VoidCallback? onPressed,
    required String text,
    required bool busy,
  }) {
    final disabled = onPressed == null;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: disabled
            ? null
            : const LinearGradient(
                colors: [Color(0xFF00F0FF), Color(0xFFBD00FF)],
              ),
        color: disabled ? Colors.white10 : null,
        boxShadow: disabled
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF00F0FF).withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: busy ? null : onPressed,
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.session.status == SessionStatus.signingIn;
    final hasKey = AppConfig.hasFirebaseApiKey;
    final error = _localError ?? widget.session.errorMessage;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF060913), Color(0xFF0F1524), Color(0xFF1B1429)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Cyberpunk ambient glows
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00F0FF).withOpacity(0.12),
                      blurRadius: 120,
                      spreadRadius: 40,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: -150,
              left: -150,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFBD00FF).withOpacity(0.1),
                      blurRadius: 150,
                      spreadRadius: 50,
                    ),
                  ],
                ),
              ),
            ),

            Center(
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Cyberpunk Header Logo/Title
                        Text(
                          'TESSERACT 4D',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 3.0,
                            shadows: [
                              Shadow(
                                color: const Color(0xFF00F0FF).withOpacity(0.8),
                                blurRadius: 15,
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'DARTSTREAM E2E CONSOLE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFBD00FF),
                            letterSpacing: 4.0,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),

                        // Glassmorphic Card
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 36,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.35),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  width: 1.2,
                                  color: Colors.white.withOpacity(0.08),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    _isSignUp
                                        ? 'INITIALIZE USER SESSION'
                                        : 'RESUME USER SESSION',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _isSignUp
                                        ? 'Create a secure Firebase account and provision a DartStream tenant.'
                                        : 'Authenticate credentials to connect back to your active sandbox.',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  if (!hasKey) ...[
                                    const SizedBox(height: 20),
                                    const _CyberBanner(
                                      isError: true,
                                      text:
                                          'No Firebase API key detected. Please run the client with:\n--dart-define=FIREBASE_API_KEY=<key>',
                                    ),
                                  ],
                                  const SizedBox(height: 28),

                                  // Sliding Mode Switcher
                                  _ModeTabSelector(
                                    currentMode: _mode,
                                    onChanged: busy ? (_) {} : _setMode,
                                  ),
                                  const SizedBox(height: 24),

                                  // Email Field
                                  TextField(
                                    controller: _email,
                                    keyboardType: TextInputType.emailAddress,
                                    autofillHints: const [AutofillHints.email],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                    decoration: _customInputDecoration(
                                      labelText: 'Security Email',
                                      hintText: 'user@aortem.com',
                                      prefixIcon: Icons.email_outlined,
                                    ),
                                    enabled: !busy,
                                  ),
                                  const SizedBox(height: 16),

                                  // Password Field
                                  TextField(
                                    controller: _password,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                    obscureText: _obscurePassword,
                                    decoration: _customInputDecoration(
                                      labelText: 'Access Password',
                                      hintText: '••••••••',
                                      prefixIcon: Icons.lock_outline,
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: Colors.white54,
                                          size: 18,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _obscurePassword =
                                                !_obscurePassword;
                                          });
                                        },
                                      ),
                                      helperText: 'At least 6 characters',
                                    ),
                                    enabled: !busy,
                                    onSubmitted: (_) =>
                                        _isSignUp ? null : _submit(),
                                  ),

                                  if (_isSignUp) ...[
                                    const SizedBox(height: 16),
                                    // Confirm Password Field
                                    TextField(
                                      controller: _confirm,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                      obscureText: _obscureConfirm,
                                      decoration: _customInputDecoration(
                                        labelText: 'Confirm Password',
                                        hintText: '••••••••',
                                        prefixIcon:
                                            Icons.verified_user_outlined,
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _obscureConfirm
                                                ? Icons.visibility_off_outlined
                                                : Icons.visibility_outlined,
                                            color: Colors.white54,
                                            size: 18,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _obscureConfirm =
                                                  !_obscureConfirm;
                                            });
                                          },
                                        ),
                                      ),
                                      enabled: !busy,
                                      onSubmitted: (_) => _submit(),
                                    ),
                                  ],
                                  const SizedBox(height: 32),

                                  // Action Button
                                  _buildActionButton(
                                    onPressed: busy || !hasKey ? null : _submit,
                                    text: _isSignUp
                                        ? 'PROVISION SESSION'
                                        : 'ESTABLISH SESSION',
                                    busy: busy,
                                  ),

                                  if (error != null) ...[
                                    const SizedBox(height: 20),
                                    _CyberBanner(isError: true, text: error),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTabSelector extends StatelessWidget {
  const _ModeTabSelector({required this.currentMode, required this.onChanged});

  final AuthMode currentMode;
  final ValueChanged<AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            alignment: currentMode == AuthMode.signUp
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00F0FF), Color(0xFFBD00FF)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00F0FF).withOpacity(0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(AuthMode.signUp),
                  child: Center(
                    child: Text(
                      'Create Account',
                      style: TextStyle(
                        color: currentMode == AuthMode.signUp
                            ? Colors.white
                            : Colors.white54,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(AuthMode.signIn),
                  child: Center(
                    child: Text(
                      'Sign In',
                      style: TextStyle(
                        color: currentMode == AuthMode.signIn
                            ? Colors.white
                            : Colors.white54,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CyberBanner extends StatelessWidget {
  const _CyberBanner({required this.isError, required this.text});

  final bool isError;
  final String text;

  @override
  Widget build(BuildContext context) {
    final accentColor = isError
        ? const Color(0xFFFF0055)
        : const Color(0xFFFFB800);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withOpacity(0.25), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.warning_amber_rounded,
            color: accentColor,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: accentColor.withOpacity(0.95),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
