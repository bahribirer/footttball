import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:footttball/core/session.dart';
import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/models/team_model.dart';
import 'package:footttball/data/services/game_socket.dart';
import 'package:footttball/features/games/category_race/category_race_screen.dart';
import 'package:footttball/features/games/last_letter/last_letter_screen.dart';
import 'package:footttball/features/games/player_guess/player_guess_screen.dart';
import 'package:footttball/features/games/tiki_taka_toe/tiki_taka_toe_screen.dart';
import 'package:footttball/shared/widgets/app_background.dart';

/// Oyun başlamadan önceki karşılaşma ekranı.
class VsScreen extends StatefulWidget {
  const VsScreen({super.key, required this.mode});

  final GameMode mode;

  @override
  State<VsScreen> createState() => _VsScreenState();
}

class _VsScreenState extends State<VsScreen> with TickerProviderStateMixin {
  static const _introDuration = Duration(milliseconds: 3000);

  late final AnimationController _left;
  late final AnimationController _right;
  late final AnimationController _badge;
  late final AnimationController _rays;
  late final AnimationController _flash;

  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();

    _left = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);
    _right = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);
    _badge = AnimationController(
        duration: const Duration(milliseconds: 700), vsync: this);
    _flash = AnimationController(
        duration: const Duration(milliseconds: 550), vsync: this);
    _rays = AnimationController(duration: const Duration(seconds: 12), vsync: this)
      ..repeat();

    _play();
  }

  Future<void> _play() async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    _left.forward();
    _right.forward();

    await Future<void>.delayed(const Duration(milliseconds: 520));
    if (!mounted) return;
    _badge.forward();
    _flash.forward();

    _navigationTimer = Timer(_introDuration, _openGame);
  }

  void _openGame() {
    if (!mounted) return;

    final payload = GameSocket.instance.startPayload;

    final Widget game = switch (widget.mode) {
      GameMode.tikiTakaToe => TikiTakaToeScreen(
          teammodel: TeamModel(
            nations: (payload['nations'] as List?)?.cast<String>() ?? const [],
            clubs: (payload['clubs'] as List?)?.cast<String>() ?? const [],
          ),
          leagueId: payload['league_id'] as String? ?? Session.instance.leagueId,
          roundCount: payload['round_count'] as int? ?? Session.instance.roundCount,
        ),
      GameMode.playerGuess => const PlayerGuessScreen(),
      GameMode.lastLetter => const LastLetterScreen(),
      GameMode.categoryRace => const CategoryRaceScreen(),
    };

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, animation, __) =>
            FadeTransition(opacity: animation, child: game),
      ),
    );
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _left.dispose();
    _right.dispose();
    _badge.dispose();
    _rays.dispose();
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final socket = GameSocket.instance;
    final accent = widget.mode.colors.last;

    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [
          PlainBackground(accent: widget.mode.colors.first),

          // Merkezden yayılan, yavaşça dönen ışık huzmeleri
          AnimatedBuilder(
            animation: _rays,
            builder: (context, _) => CustomPaint(
              size: Size.infinite,
              painter: _RayPainter(
                progress: _rays.value,
                color: accent.withOpacity(0.10),
              ),
            ),
          ),

          // VS belirdiğinde tek seferlik parlama
          AnimatedBuilder(
            animation: _flash,
            builder: (context, _) {
              final t = Curves.easeOutCubic.transform(_flash.value);
              if (t == 0) return const SizedBox.shrink();
              return IgnorePointer(
                child: Opacity(
                  opacity: (1 - t) * 0.5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        radius: 0.35 + t * 1.1,
                        colors: [accent.withOpacity(0.65), Colors.transparent],
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              );
            },
          ),

          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                _ModeBanner(mode: widget.mode, controller: _badge),
                const SizedBox(height: 34),
                _PlayerSide(
                  name: socket.myName,
                  subtitle: 'SEN',
                  accent: Colors.cyanAccent,
                  controller: _left,
                  fromLeft: true,
                ),
                const SizedBox(height: 6),
                _VsBadge(controller: _badge, accent: accent),
                const SizedBox(height: 6),
                _PlayerSide(
                  name: socket.opponentName,
                  subtitle: 'RAKİP',
                  accent: accent,
                  controller: _right,
                  fromLeft: false,
                ),
                const Spacer(),
                FadeTransition(
                  opacity: _badge,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 34),
                    child: Text(
                      'MAÇ BAŞLIYOR',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Üstte beliren mod şeridi.
class _ModeBanner extends StatelessWidget {
  const _ModeBanner({required this.mode, required this.controller});

  final GameMode mode;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: controller,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: mode.colors),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: mode.colors.last.withOpacity(0.45), blurRadius: 20),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(mode.icon, color: Colors.white, size: 16),
            const SizedBox(width: 9),
            Text(
              mode.title.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kenardan kayarak gelen oyuncu şeridi.
class _PlayerSide extends StatelessWidget {
  const _PlayerSide({
    required this.name,
    required this.subtitle,
    required this.accent,
    required this.controller,
    required this.fromLeft,
  });

  final String name;
  final String subtitle;
  final Color accent;
  final AnimationController controller;
  final bool fromLeft;

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: Offset(fromLeft ? -1.4 : 1.4, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOutBack));

    final avatar = Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withOpacity(0.5),
        border: Border.all(color: accent, width: 2),
        boxShadow: [BoxShadow(color: accent.withOpacity(0.45), blurRadius: 18)],
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(color: accent, fontSize: 26, fontWeight: FontWeight.w900),
        ),
      ),
    );

    final texts = Column(
      crossAxisAlignment:
          fromLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(
            color: accent,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.4,
          ),
        ),
      ],
    );

    return SlideTransition(
      position: slide,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        margin: EdgeInsets.only(right: fromLeft ? 40 : 0, left: fromLeft ? 0 : 40),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(fromLeft ? 0 : 44),
            right: Radius.circular(fromLeft ? 44 : 0),
          ),
          border: Border.all(color: accent.withOpacity(0.45), width: 1.6),
          gradient: LinearGradient(
            begin: fromLeft ? Alignment.centerLeft : Alignment.centerRight,
            end: fromLeft ? Alignment.centerRight : Alignment.centerLeft,
            colors: [Colors.black.withOpacity(0.65), accent.withOpacity(0.18)],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: fromLeft
              ? [avatar, const SizedBox(width: 16), Flexible(child: texts)]
              : [Flexible(child: texts), const SizedBox(width: 16), avatar],
        ),
      ),
    );
  }
}

/// Ortadaki VS rozeti.
class _VsBadge extends StatelessWidget {
  const _VsBadge({required this.controller, required this.accent});

  final AnimationController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: controller, curve: Curves.elasticOut),
      child: SizedBox(
        width: 132,
        height: 132,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: accent.withOpacity(0.28), width: 1.5),
              ),
            ),
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF0055), Color(0xFF8000FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF0055).withOpacity(0.55),
                    blurRadius: 40,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'VS',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w900,
                    fontSize: 42,
                    color: Colors.white,
                    shadows: [
                      Shadow(color: Colors.black45, offset: Offset(2, 3), blurRadius: 6),
                    ],
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

/// Merkezden yayılan, yavaşça dönen ışık huzmeleri.
class _RayPainter extends CustomPainter {
  _RayPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.longestSide;
    final paint = Paint()..color = color;

    const rayCount = 12;
    for (var i = 0; i < rayCount; i++) {
      final angle = (i / rayCount) * 2 * math.pi + progress * 2 * math.pi;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + radius * math.cos(angle - 0.06),
            center.dy + radius * math.sin(angle - 0.06))
        ..lineTo(center.dx + radius * math.cos(angle + 0.06),
            center.dy + radius * math.sin(angle + 0.06))
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_RayPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
