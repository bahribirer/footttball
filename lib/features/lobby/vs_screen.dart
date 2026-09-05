import 'dart:async';

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

/// Oyun başlamadan önceki kısa "karşılaşma" animasyonu.
class VsScreen extends StatefulWidget {
  const VsScreen({super.key, required this.mode});

  final GameMode mode;

  @override
  State<VsScreen> createState() => _VsScreenState();
}

class _VsScreenState extends State<VsScreen> with TickerProviderStateMixin {
  static const _introDuration = Duration(milliseconds: 2600);

  late final AnimationController _leftController;
  late final AnimationController _rightController;
  late final AnimationController _badgeController;
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();

    _leftController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _rightController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _badgeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _play();
  }

  Future<void> _play() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    _leftController.forward();
    _rightController.forward();

    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _badgeController.forward();

    _navigationTimer = Timer(_introDuration, _openGame);
  }

  void _openGame() {
    if (!mounted) return;

    final socket = GameSocket.instance;
    final payload = socket.startPayload;

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
      MaterialPageRoute(builder: (_) => game),
    );
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _leftController.dispose();
    _rightController.dispose();
    _badgeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final socket = GameSocket.instance;
    final myName = socket.myName;
    final rivalName = socket.opponentName;

    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [
          PlainBackground(accent: widget.mode.colors.first),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 90),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: widget.mode.colors),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(
                  widget.mode.title.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              _PlayerBanner(
                name: myName,
                accent: Colors.cyanAccent,
                controller: _leftController,
                fromLeft: true,
                icon: Icons.person,
              ),
              const SizedBox(height: 18),
              ScaleTransition(
                scale: CurvedAnimation(parent: _badgeController, curve: Curves.elasticOut),
                child: Container(
                  height: 116,
                  width: 116,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF0055), Color(0xFF8000FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF0055).withOpacity(0.6),
                        blurRadius: 45,
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
                        fontSize: 46,
                        color: Colors.white,
                        shadows: [
                          Shadow(color: Colors.black45, offset: Offset(3, 3), blurRadius: 5),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _PlayerBanner(
                name: rivalName,
                accent: Colors.purpleAccent,
                controller: _rightController,
                fromLeft: false,
                icon: Icons.person_outline,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayerBanner extends StatelessWidget {
  const _PlayerBanner({
    required this.name,
    required this.accent,
    required this.controller,
    required this.fromLeft,
    required this.icon,
  });

  final String name;
  final Color accent;
  final AnimationController controller;
  final bool fromLeft;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: Offset(fromLeft ? -1.5 : 1.5, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOutBack));

    final label = Text(
      name.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.8,
      ),
    );

    return SlideTransition(
      position: slide,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
        margin: EdgeInsets.only(
          right: fromLeft ? 44 : 0,
          left: fromLeft ? 0 : 44,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(fromLeft ? 0 : 46),
            right: Radius.circular(fromLeft ? 46 : 0),
          ),
          border: Border.all(color: accent.withOpacity(0.5), width: 2),
          gradient: LinearGradient(
            colors: fromLeft
                ? [Colors.black54, accent.withOpacity(0.2)]
                : [accent.withOpacity(0.2), Colors.black54],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: fromLeft
              ? [Icon(icon, color: accent, size: 28), const SizedBox(width: 14), Flexible(child: label)]
              : [Flexible(child: label), const SizedBox(width: 14), Icon(icon, color: accent, size: 28)],
        ),
      ),
    );
  }
}
