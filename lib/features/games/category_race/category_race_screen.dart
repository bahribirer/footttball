import 'package:flutter/material.dart';

import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/models/room_models.dart';
import 'package:footttball/features/games/widgets/clock_game_scaffold.dart';

/// Kategori Yarışı modu: verilen kategoriye uyan futbolcular sırayla yazılır.
class CategoryRaceScreen extends StatelessWidget {
  const CategoryRaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ClockGameScaffold(
      mode: GameMode.categoryRace,
      inputHint: 'Kategoriye uyan futbolcu...',
      emptyHistoryText: 'Kategoriye uyan ilk futbolcuyu yaz',
      buildInfoPanel: (context, state) => _CategoryPanel(state: state),
    );
  }
}

class _CategoryPanel extends StatelessWidget {
  const _CategoryPanel({required this.state});

  final ClockGameState state;

  @override
  Widget build(BuildContext context) {
    final colors = GameMode.categoryRace.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colors.first.withOpacity(0.7), colors.last.withOpacity(0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.22), width: 1.4),
          boxShadow: [
            BoxShadow(color: colors.first.withOpacity(0.35), blurRadius: 18),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.category_rounded, color: Colors.white70, size: 15),
                const SizedBox(width: 6),
                Text(
                  'KATEGORİ',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.72),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              state.categoryLabel ?? 'Kategori yükleniyor...',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17.5,
                fontWeight: FontWeight.w900,
                height: 1.3,
              ),
            ),
            if (state.examples.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(color: Colors.white.withOpacity(0.2), height: 1),
              const SizedBox(height: 10),
              Text(
                'Örnek doğru cevaplar',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 10.5,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: state.examples
                    .map((name) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            name,
                            style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
