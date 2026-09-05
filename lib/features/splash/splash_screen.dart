import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:footttball/features/onboarding/onboarding_screen.dart';
import 'package:footttball/shared/widgets/app_background.dart';

/// Açılış ekranı: logo canlanır, ardından tanıtıma geçilir.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entry;
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    Future<void>.delayed(const Duration(milliseconds: 2400), _next);
  }

  void _next() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, animation, __) =>
            FadeTransition(opacity: animation, child: const OnboardingScreen()),
      ),
    );
  }

  @override
  void dispose() {
    _entry.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pop = CurvedAnimation(parent: _entry, curve: Curves.easeOutBack);
    final fade = CurvedAnimation(
      parent: _entry,
      curve: const Interval(0.35, 1, curve: Curves.easeOut),
    );

    return Scaffold(
      body: GestureDetector(
        onTap: _next,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const PlainBackground(accent: Color(0xFF6A11CB)),

            // Dönen ışık halkası
            AnimatedBuilder(
              animation: _spin,
              builder: (context, child) => Transform.rotate(
                angle: _spin.value * 2 * math.pi,
                child: child,
              ),
              child: Container(
                width: 250,
                height: 250,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [
                      Colors.transparent,
                      Color(0x552575FC),
                      Color(0x88CC44FF),
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.35, 0.6, 1.0],
                  ),
                ),
              ),
            ),

            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: pop,
                  child: Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: Colors.white24, width: 2.5),
                      boxShadow: const [
                        BoxShadow(color: Color(0x882575FC), blurRadius: 46, spreadRadius: 4),
                      ],
                    ),
                    child: const Icon(Icons.sports_soccer_rounded,
                        color: Colors.white, size: 68),
                  ),
                ),
                const SizedBox(height: 34),
                FadeTransition(
                  opacity: fade,
                  child: const NeonTitle('TIKI TAKA TOE', fontSize: 32),
                ),
                const SizedBox(height: 12),
                FadeTransition(
                  opacity: fade,
                  child: Text(
                    'FUTBOL BİLGİ DÜELLOSU',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                  ),
                ),
              ],
            ),

            Positioned(
              bottom: 46,
              child: FadeTransition(
                opacity: fade,
                child: const _LoadingDots(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingDots extends StatefulWidget {
  const _LoadingDots();

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (index) {
          final phase = (_controller.value + index * 0.22) % 1.0;
          final wave = math.sin(phase * math.pi).clamp(0.0, 1.0);
          return Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.25 + 0.55 * wave),
            ),
          );
        }),
      ),
    );
  }
}
