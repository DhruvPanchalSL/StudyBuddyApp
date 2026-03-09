import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'login_success_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  bool isLogin = true;
  bool isLoading = false;
  bool _obscurePassword = true;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  late AnimationController _bgAnimController;
  late AnimationController _formAnimController;
  late Animation<double> _formSlideAnim;
  late Animation<double> _formFadeAnim;
  late List<_FloatingParticle> _particles;

  static const Color _green = Color(0xFF7ED957);
  static const Color _bgColor = Color(0xFFF5FCF0);
  static const Color _textDark = Color(0xFF111827);
  static const Color _textGray = Color(0xFF6B7280);
  static const Color _borderColor = Color(0xFFE5E7EB);

  @override
  void initState() {
    super.initState();
    _bgAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();

    _formAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _formSlideAnim = Tween<double>(begin: 28, end: 0).animate(
      CurvedAnimation(parent: _formAnimController, curve: Curves.easeOut),
    );
    _formFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _formAnimController, curve: Curves.easeOut),
    );
    _formAnimController.forward();

    final rng = math.Random();
    _particles = List.generate(
      16,
      (i) => _FloatingParticle(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: 5 + rng.nextDouble() * 9,
        speed: 0.2 + rng.nextDouble() * 0.45,
        phase: rng.nextDouble() * math.pi * 2,
      ),
    );
  }

  @override
  void dispose() {
    _bgAnimController.dispose();
    _formAnimController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _switchMode() {
    _formAnimController.reset();
    setState(() {
      isLogin = !isLogin;
      _emailController.clear();
      _passwordController.clear();
      _nameController.clear();
    });
    _formAnimController.forward();
  }

  Future<void> _submit() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showError('Please fill all fields');
      return;
    }
    if (!isLogin && _nameController.text.isEmpty) {
      _showError('Please enter your name');
      return;
    }
    setState(() => isLoading = true);

    try {
      if (isLogin) {
        await _auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        final cred = await _auth.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        // Update display name in background — don't await so we don't delay
        // the success screen from showing
        cred.user?.updateDisplayName(_nameController.text.trim());
      }

      // Push success screen immediately after auth — before StreamBuilder
      // has a chance to rebuild and switch to HomeScreen
      if (mounted) {
        await Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const LoginSuccessScreen(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = 'An error occurred.';
      if (e.code == 'user-not-found')
        message = 'No account found for this email.';
      else if (e.code == 'wrong-password')
        message = 'Incorrect password.';
      else if (e.code == 'email-already-in-use')
        message = 'This email is already registered.';
      else if (e.code == 'weak-password')
        message = 'Password must be at least 6 characters.';
      else if (e.code == 'invalid-email')
        message = 'Please enter a valid email.';
      else if (e.code == 'invalid-credential')
        message = 'Invalid email or password.';
      _showError(message);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          // Animated particles
          AnimatedBuilder(
            animation: _bgAnimController,
            builder: (context, _) => CustomPaint(
              size: size,
              painter: _ParticlePainter(
                progress: _bgAnimController.value,
                particles: _particles,
                color: _green,
              ),
            ),
          ),

          // Top blob
          Positioned(
            top: -110,
            right: -70,
            child: AnimatedBuilder(
              animation: _bgAnimController,
              builder: (_, __) => Transform.scale(
                scale:
                    1 + 0.06 * math.sin(_bgAnimController.value * math.pi * 2),
                child: Container(
                  width: 340,
                  height: 340,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [_green.withOpacity(0.22), _green.withOpacity(0)],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom blob
          Positioned(
            bottom: -90,
            left: -70,
            child: AnimatedBuilder(
              animation: _bgAnimController,
              builder: (_, __) => Transform.scale(
                scale:
                    1 + 0.05 * math.cos(_bgAnimController.value * math.pi * 2),
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF4CAF50).withOpacity(0.14),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 50),

                    // ── Title ──
                    const Text(
                      'Study Buddy AI',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: _textDark,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your AI-powered learning companion',
                      style: TextStyle(
                        fontSize: 14,
                        color: _textGray,
                        fontWeight: FontWeight.w400,
                      ),
                    ),

                    const SizedBox(height: 44),

                    // ── Mode Tabs ──
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.07),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildModeTab('Sign In', true),
                          _buildModeTab('Sign Up', false),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),

                    // ── Form Card ──
                    AnimatedBuilder(
                      animation: _formAnimController,
                      builder: (_, child) => Transform.translate(
                        offset: Offset(0, _formSlideAnim.value),
                        child: Opacity(
                          opacity: _formFadeAnim.value,
                          child: child,
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(26),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: _borderColor),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 28,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: Column(
                                key: ValueKey(isLogin),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isLogin
                                        ? 'Welcome back 👋'
                                        : 'Create account ✨',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: _textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isLogin
                                        ? 'Sign in to continue your learning journey'
                                        : 'Start your AI-powered study sessions today',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: _textGray,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 28),

                            if (!isLogin) ...[
                              _buildLabel('Full Name'),
                              const SizedBox(height: 8),
                              _buildTextField(
                                controller: _nameController,
                                hint: 'Your full name',
                                icon: Icons.person_outline_rounded,
                              ),
                              const SizedBox(height: 18),
                            ],

                            _buildLabel('Email Address'),
                            const SizedBox(height: 8),
                            _buildTextField(
                              controller: _emailController,
                              hint: 'Enter your email',
                              icon: Icons.mail_outline_rounded,
                              keyboardType: TextInputType.emailAddress,
                            ),

                            const SizedBox(height: 18),

                            _buildLabel('Password'),
                            const SizedBox(height: 8),
                            _buildTextField(
                              controller: _passwordController,
                              hint: isLogin
                                  ? 'Enter your password'
                                  : 'Create a password',
                              icon: Icons.lock_outline_rounded,
                              obscure: _obscurePassword,
                              suffix: IconButton(
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  size: 18,
                                  color: _textGray,
                                ),
                              ),
                            ),

                            const SizedBox(height: 28),

                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: isLoading ? null : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _green,
                                  disabledBackgroundColor: _green.withOpacity(
                                    0.5,
                                  ),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: isLoading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        isLogin ? 'Sign In' : 'Create Account',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    GestureDetector(
                      onTap: _switchMode,
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: isLogin
                                  ? "Don't have an account? "
                                  : "Already have an account? ",
                              style: const TextStyle(
                                color: _textGray,
                                fontSize: 14,
                              ),
                            ),
                            TextSpan(
                              text: isLogin ? 'Sign Up' : 'Sign In',
                              style: const TextStyle(
                                color: _green,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 36),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab(String label, bool forLogin) {
    final isActive = isLogin == forLogin;
    return GestureDetector(
      onTap: isActive ? null : _switchMode,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? _green : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isActive
              ? [BoxShadow(color: _green.withOpacity(0.28), blurRadius: 12)]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? Colors.white : _textGray,
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _textDark,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
    Widget? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: const TextStyle(color: _textDark, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _textGray, fontSize: 14),
          prefixIcon: Icon(icon, color: _textGray, size: 20),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}

class _FloatingParticle {
  final double x, y, size, speed, phase;
  const _FloatingParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.phase,
  });
}

class _ParticlePainter extends CustomPainter {
  final double progress;
  final List<_FloatingParticle> particles;
  final Color color;
  const _ParticlePainter({
    required this.progress,
    required this.particles,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      final t = (progress * p.speed + p.phase) % 1.0;
      final dy = size.height - t * size.height * 1.3;
      final dx =
          size.width * p.x +
          math.sin(progress * math.pi * 2 * p.speed + p.phase) * 20;
      final opacity = (math.sin(t * math.pi)).clamp(0.0, 1.0) * 0.16;
      paint.color = color.withOpacity(opacity);
      canvas.drawCircle(Offset(dx, dy), p.size / 2, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}
