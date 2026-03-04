import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:StudyBuddy/main.dart' show HomeScreen;

class LoginSuccessScreen extends StatefulWidget {
  const LoginSuccessScreen({super.key});

  @override
  State<LoginSuccessScreen> createState() => _LoginSuccessScreenState();
}

class _LoginSuccessScreenState extends State<LoginSuccessScreen>
    with TickerProviderStateMixin {
  static const Color _green = Color(0xFF7ED957);
  static const Color _darkGreen = Color(0xFF4CAF50);
  static const Color _bgColor = Color(0xFFF5FCF0);
  static const Color _textDark = Color(0xFF111827);

  // ── Ripple waves expanding outward
  late AnimationController _rippleCtrl;

  // ── Check circle entry
  late AnimationController _circleCtrl;
  late Animation<double> _circleScale;
  late Animation<double> _circleOpacity;
  late Animation<double> _checkDraw; // stroke progress for check

  // ── Confetti burst
  late AnimationController _confettiCtrl;
  late List<_ConfettiPiece> _confetti;

  // ── Text
  late AnimationController _textCtrl;
  late Animation<double> _title1Opacity;
  late Animation<Offset> _title1Slide;
  late Animation<double> _title2Opacity;
  late Animation<Offset> _title2Slide;

  // ── Stars / sparkles orbiting
  late AnimationController _orbitCtrl;

  // ── Exit
  late AnimationController _exitCtrl;
  late Animation<double> _exitOpacity;

  @override
  void initState() {
    super.initState();

    // Ripple
    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // Circle + check
    _circleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _circleScale = CurvedAnimation(
      parent: _circleCtrl,
      curve: const Interval(0, 0.6, curve: Curves.elasticOut),
    );
    _circleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _circleCtrl,
        curve: const Interval(0, 0.25, curve: Curves.easeIn),
      ),
    );
    _checkDraw = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _circleCtrl,
        curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
      ),
    );

    // Confetti
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    final rng = math.Random();
    _confetti = List.generate(40, (i) => _ConfettiPiece(
      x: 0.3 + rng.nextDouble() * 0.4,
      angle: rng.nextDouble() * math.pi * 2,
      speed: 80 + rng.nextDouble() * 200,
      size: 5 + rng.nextDouble() * 8,
      color: [
        _green,
        const Color(0xFFFFC107),
        const Color(0xFF29B6F6),
        const Color(0xFFFF7043),
        const Color(0xFFBA68C8),
        const Color(0xFF4CAF50),
      ][rng.nextInt(6)],
      rotationSpeed: (rng.nextDouble() - 0.5) * 8,
      isRect: rng.nextBool(),
    ));

    // Text
    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _title1Opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _textCtrl, curve: const Interval(0, 0.55, curve: Curves.easeOut)),
    );
    _title1Slide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(parent: _textCtrl, curve: const Interval(0, 0.55, curve: Curves.easeOut)),
    );
    _title2Opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _textCtrl, curve: const Interval(0.35, 1.0, curve: Curves.easeOut)),
    );
    _title2Slide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(parent: _textCtrl, curve: const Interval(0.35, 1.0, curve: Curves.easeOut)),
    );

    // Orbit
    _orbitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    // Exit
    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _exitOpacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Curves.easeInCubic),
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 150));
    _rippleCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 250));
    _circleCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 500));
    _confettiCtrl.forward();
    _textCtrl.forward();

    // Hold for a moment, then navigate
    await Future.delayed(const Duration(milliseconds: 3200));
    await _exitCtrl.forward();

    if (mounted) {
      // HomeScreen is already the base route (StreamBuilder shows it once
      // kShowLoginSuccess == false). We just pop this screen off.
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 600),
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
        (route) => false,
      );
    }
  }

  @override
  void dispose() {
    _rippleCtrl.dispose();
    _circleCtrl.dispose();
    _confettiCtrl.dispose();
    _textCtrl.dispose();
    _orbitCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final center = Offset(size.width / 2, size.height * 0.42);

    return Scaffold(
      backgroundColor: _bgColor,
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _rippleCtrl, _circleCtrl, _confettiCtrl,
          _textCtrl, _orbitCtrl, _exitCtrl,
        ]),
        builder: (context, _) {
          return Opacity(
            opacity: _exitOpacity.value,
            child: Stack(
              children: [
                // ── Background soft radial ──
                Positioned.fill(
                  child: CustomPaint(
                    painter: _BackgroundPainter(
                      circleProgress: _circleCtrl.value,
                      green: _green,
                      center: center,
                    ),
                  ),
                ),

                // ── Expanding ripple waves ──
                Positioned.fill(
                  child: CustomPaint(
                    painter: _RipplePainter(
                      progress: _rippleCtrl.value,
                      center: center,
                      color: _green,
                    ),
                  ),
                ),

                // ── Confetti burst ──
                if (_confettiCtrl.value > 0)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ConfettiPainter(
                        progress: _confettiCtrl.value,
                        pieces: _confetti,
                        center: center,
                      ),
                    ),
                  ),

                // ── Orbiting sparkles ──
                if (_circleCtrl.value > 0.5)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _OrbitPainter(
                        progress: _orbitCtrl.value,
                        center: center,
                        opacity: ((_circleCtrl.value - 0.5) * 2).clamp(0.0, 1.0),
                      ),
                    ),
                  ),

                // ── Central circle + check ──
                Positioned(
                  left: center.dx - 60,
                  top: center.dy - 60,
                  child: Opacity(
                    opacity: _circleOpacity.value,
                    child: Transform.scale(
                      scale: _circleScale.value.clamp(0.0, 1.08),
                      child: SizedBox(
                        width: 120,
                        height: 120,
                        child: CustomPaint(
                          painter: _CheckCirclePainter(
                            progress: _checkDraw.value,
                            color: _green,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Text ──
                Positioned(
                  left: 0,
                  right: 0,
                  top: center.dy + 90,
                  child: Column(
                    children: [
                      FadeTransition(
                        opacity: _title1Opacity,
                        child: SlideTransition(
                          position: _title1Slide,
                          child: const Text(
                            'All Set! 🎉',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: _textDark,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FadeTransition(
                        opacity: _title2Opacity,
                        child: SlideTransition(
                          position: _title2Slide,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 44),
                            child: Text(
                              'Unlocking ultimate powers\nfor your knowledge ✨',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 17,
                                height: 1.6,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 48),
                      Opacity(
                        opacity: _title2Opacity.value,
                        child: _AnimatedDots(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ────────────────────────────────────────────────
// Background radial painter
// ────────────────────────────────────────────────
class _BackgroundPainter extends CustomPainter {
  final double circleProgress;
  final Color green;
  final Offset center;
  const _BackgroundPainter({required this.circleProgress, required this.green, required this.center});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          (center.dx / size.width) * 2 - 1,
          (center.dy / size.height) * 2 - 1,
        ),
        radius: 0.8,
        colors: [
          green.withOpacity(0.12 * circleProgress.clamp(0.0, 1.0)),
          const Color(0xFFF5FCF0).withOpacity(0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) => old.circleProgress != circleProgress;
}

// ────────────────────────────────────────────────
// Ripple waves
// ────────────────────────────────────────────────
class _RipplePainter extends CustomPainter {
  final double progress;
  final Offset center;
  final Color color;
  const _RipplePainter({required this.progress, required this.center, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const numWaves = 4;
    for (int i = 0; i < numWaves; i++) {
      final delay = i / numWaves;
      final t = ((progress - delay) * 1.6).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final radius = t * 220;
      final opacity = (1 - t) * 0.18;
      final paint = Paint()
        ..color = color.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.progress != progress;
}

// ────────────────────────────────────────────────
// Check circle painted
// ────────────────────────────────────────────────
class _CheckCirclePainter extends CustomPainter {
  final double progress;
  final Color color;
  const _CheckCirclePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Outer glow ring
    canvas.drawCircle(center, radius,
        Paint()..color = color.withOpacity(0.12));
    canvas.drawCircle(center, radius * 0.8,
        Paint()..color = color.withOpacity(0.2));
    // Main circle
    canvas.drawCircle(center, radius * 0.68, Paint()..color = color);

    // Check mark drawn progressively
    if (progress > 0) {
      final checkPath = Path();
      // Checkmark points: left leg then right leg
      final p1 = Offset(center.dx - 20, center.dy + 2);
      final p2 = Offset(center.dx - 6, center.dy + 16);
      final p3 = Offset(center.dx + 22, center.dy - 14);

      // Two segments of the check
      if (progress <= 0.5) {
        final t = progress / 0.5;
        checkPath.moveTo(p1.dx, p1.dy);
        checkPath.lineTo(
          p1.dx + (p2.dx - p1.dx) * t,
          p1.dy + (p2.dy - p1.dy) * t,
        );
      } else {
        final t = (progress - 0.5) / 0.5;
        checkPath.moveTo(p1.dx, p1.dy);
        checkPath.lineTo(p2.dx, p2.dy);
        checkPath.lineTo(
          p2.dx + (p3.dx - p2.dx) * t,
          p2.dy + (p3.dy - p2.dy) * t,
        );
      }

      final checkPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(checkPath, checkPaint);
    }
  }

  @override
  bool shouldRepaint(_CheckCirclePainter old) => old.progress != progress;
}

// ────────────────────────────────────────────────
// Confetti painter
// ────────────────────────────────────────────────
class _ConfettiPiece {
  final double x, angle, speed, size, rotationSpeed;
  final Color color;
  final bool isRect;
  const _ConfettiPiece({
    required this.x, required this.angle, required this.speed,
    required this.size, required this.color, required this.rotationSpeed,
    required this.isRect,
  });
}

class _ConfettiPainter extends CustomPainter {
  final double progress;
  final List<_ConfettiPiece> pieces;
  final Offset center;
  const _ConfettiPainter({required this.progress, required this.pieces, required this.center});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final eased = Curves.easeOut.transform(progress.clamp(0.0, 1.0));
      final dist = p.speed * eased;
      final grav = 180 * eased * eased;
      final dx = center.dx + math.cos(p.angle) * dist;
      final dy = center.dy + math.sin(p.angle) * dist + grav;

      final opacity = (1 - progress * 0.85).clamp(0.0, 1.0);
      final rotation = p.rotationSpeed * progress * math.pi;

      final paint = Paint()..color = p.color.withOpacity(opacity);
      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(rotation);

      if (p.isRect) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
            const Radius.circular(2),
          ),
          paint,
        );
      } else {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

// ────────────────────────────────────────────────
// Orbiting sparkle painter
// ────────────────────────────────────────────────
class _OrbitPainter extends CustomPainter {
  final double progress;
  final Offset center;
  final double opacity;
  const _OrbitPainter({required this.progress, required this.center, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    const count = 6;
    for (int i = 0; i < count; i++) {
      final angle = (i / count) * math.pi * 2 + progress * math.pi * 2;
      final orbitRadius = 80.0;
      final dx = center.dx + math.cos(angle) * orbitRadius;
      final dy = center.dy + math.sin(angle) * orbitRadius;

      final phase = (progress * 4 + i / count) % 1.0;
      final starSize = 4 + 3 * math.sin(phase * math.pi);
      final paint = Paint()
        ..color = const Color(0xFF7ED957).withOpacity(opacity * 0.75);
      _drawStar(canvas, Offset(dx, dy), starSize, paint);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = (i * 2 * math.pi / 5) - math.pi / 2;
      final innerAngle = outerAngle + math.pi / 5;
      final outer = Offset(
        center.dx + r * math.cos(outerAngle),
        center.dy + r * math.sin(outerAngle),
      );
      final inner = Offset(
        center.dx + (r * 0.4) * math.cos(innerAngle),
        center.dy + (r * 0.4) * math.sin(innerAngle),
      );
      if (i == 0) path.moveTo(outer.dx, outer.dy);
      else path.lineTo(outer.dx, outer.dy);
      path.lineTo(inner.dx, inner.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.progress != progress || old.opacity != opacity;
}

// ────────────────────────────────────────────────
// Animated dots
// ────────────────────────────────────────────────
class _AnimatedDots extends StatefulWidget {
  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final t = ((_ctrl.value - i / 3 + 1) % 1);
          final scale = 0.5 + 0.5 * math.sin(t * math.pi);
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFF7ED957).withOpacity(0.25 + 0.75 * scale),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
