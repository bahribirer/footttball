import 'package:flutter/material.dart';

import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/models/room_models.dart';
import 'package:footttball/features/games/widgets/clock_game_scaffold.dart';

/// Son Harf modu: rakibin yazdığı futbolcunun son harfiyle başlayan
/// bir futbolcu yazılır.
class LastLetterScreen extends StatelessWidget {
  const LastLetterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ClockGameScaffold(
      mode: GameMode.lastLetter,
      inputHint: 'Futbolcu adı yaz...',
      emptyHistoryText: 'İlk futbolcuyu sen belirle — zincir seninle başlıyor',
      buildInfoPanel: (context, state) => _LetterPanel(state: state),
    );
  }
}

class _LetterPanel extends StatelessWidget {
  const _LetterPanel({required this.state});

  final ClockGameState state;

  @override
  Widget build(BuildContext context) {
    final letter = state.requiredLetter;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Text(
            letter == null ? 'SERBEST BAŞLANGIÇ' : 'BU HARFLE BAŞLA',
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: letter == null
                    ? [Colors.white24, Colors.white10]
                    : GameMode.lastLetter.colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: letter == null
                  ? null
                  : [
                      BoxShadow(
                        color: GameMode.lastLetter.colors.last.withOpacity(0.55),
                        blurRadius: 26,
                        spreadRadius: 2,
                      ),
                    ],
            ),
            child: Center(
              child: Text(
                letter?.toUpperCase() ?? '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: Colors.black38, blurRadius: 8)],
                ),
              ),
            ),
          ),
          if (state.lastAnswer != null) ...[
            const SizedBox(height: 12),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12.5),
                children: [
                  const TextSpan(text: 'Son yazılan: '),
                  TextSpan(
                    text: state.lastAnswer,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
