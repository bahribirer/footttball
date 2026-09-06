import 'package:flutter/material.dart';

import 'package:footttball/core/session.dart';
import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/features/lobby/start_page.dart';
import 'package:footttball/shared/widgets/app_background.dart';

/// İsim girildikten sonra açılan oyun modu menüsü.
class ModeSelectScreen extends StatefulWidget {
  const ModeSelectScreen({super.key});

  @override
  State<ModeSelectScreen> createState() => _ModeSelectScreenState();
}

class _ModeSelectScreenState extends State<ModeSelectScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  GameMode? _expanded;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openMode(GameMode mode) {
    Session.instance.selectedMode = mode;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StartPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final modes = GameMode.values;

    return Scaffold(
      body: Stack(
        children: [
          const PlainBackground(),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 12),
                // Oyuncu adı rozeti — arka plandaki logonun üstünde kalır.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.cyanAccent.withOpacity(0.35)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person,
                                  color: Colors.cyanAccent, size: 17),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  Session.instance.displayName.toUpperCase(),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                const NeonTitle('OYUN MODU SEÇ', fontSize: 26),
                const SizedBox(height: 5),
                Text(
                  'Rakibinle aynı modda buluşun',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
                    itemCount: modes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final mode = modes[index];
                      final animation = CurvedAnimation(
                        parent: _controller,
                        curve: Interval(
                          (index / modes.length) * 0.6,
                          1,
                          curve: Curves.easeOutBack,
                        ),
                      );

                      return AnimatedBuilder(
                        animation: animation,
                        builder: (context, child) => Opacity(
                          opacity: animation.value.clamp(0, 1),
                          child: Transform.translate(
                            offset: Offset(0, 40 * (1 - animation.value)),
                            child: child,
                          ),
                        ),
                        child: _ModeCard(
                          mode: mode,
                          expanded: _expanded == mode,
                          onToggle: () => setState(
                            () => _expanded = _expanded == mode ? null : mode,
                          ),
                          onPlay: () => _openMode(mode),
                        ),
                      );
                    },
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

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.expanded,
    required this.onToggle,
    required this.onPlay,
  });

  final GameMode mode;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      key: ValueKey('mode_card_${mode.id}'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              mode.colors.first.withOpacity(expanded ? 0.85 : 0.55),
              mode.colors.last.withOpacity(expanded ? 0.85 : 0.55),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: Colors.white.withOpacity(expanded ? 0.5 : 0.18),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: mode.colors.first.withOpacity(expanded ? 0.45 : 0.25),
              blurRadius: expanded ? 24 : 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.28),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white.withOpacity(0.25)),
                  ),
                  child: Icon(mode.icon, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mode.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        mode.tagline,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 14),
                  Text(
                    mode.description,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      key: ValueKey('play_${mode.id}'),
                      onTap: onPlay,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.play_arrow_rounded,
                                color: mode.colors.last, size: 22),
                            const SizedBox(width: 6),
                            Text(
                              'BU MODU OYNA',
                              style: TextStyle(
                                color: mode.colors.last,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
