import 'dart:async';

import 'package:flutter/material.dart';

import 'package:footttball/core/lives.dart';
import 'package:footttball/core/notices.dart';
import 'package:footttball/core/session.dart';
import 'package:footttball/core/sound.dart';
import 'package:footttball/core/theme/app_theme.dart';
import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/services/api_service.dart';
import 'package:footttball/features/daily/daily_challenge_screen.dart';
import 'package:footttball/features/leaderboard/leaderboard_screen.dart';
import 'package:footttball/features/lobby/quick_match_sheet.dart';
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
    _loadEnabledModes();
    _loadNotice();
    Lives.instance.refresh();
    // Can sayacı: dakikada bir tazelenir (pencere dolunca 10'a döner).
    _livesTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => Lives.instance.refresh(),
    );
  }

  Timer? _livesTimer;

  /// Menüye gelen oyuncu sokete bağlı değil; panodaki duyuruyu buradan alır.
  Future<void> _loadNotice() async {
    final notice = await ApiService.notice();
    if (!mounted) return;
    Notices.instance.showBoard(notice);
  }

  /// Sunucudan açık modları çeker.
  ///
  /// Yanıt gelene kadar gömülü liste gösterilir; menü boş kalmaz. Sunucu
  /// ulaşılamazsa da öyle: bir mod kapatma özelliğinin çevrimdışı bir
  /// aksaklıkta oyunu tümden kullanılamaz hale getirmesi istenmez.
  Future<void> _loadEnabledModes() async {
    final ids = await ApiService.enabledModeIds();
    if (!mounted || ids.isEmpty) return;
    setState(() => _enabledIds = ids);
  }

  /// Sunucudan gelen açık mod kimlikleri; null ise henüz yanıt yok.
  Set<String>? _enabledIds;

  @override
  void dispose() {
    _livesTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _openDaily() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DailyChallengeScreen()),
    );
  }

  void _openLeaderboard() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
    );
  }

  Future<void> _openQuickMatch() async {
    if (!await Lives.instance.ensure(context)) return;
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => QuickMatchSheet(
        modes: _enabledIds == null
            ? GameMode.values
            : GameMode.values
                .where((m) => _enabledIds!.contains(m.id))
                .toList(),
      ),
    );
  }

  Future<void> _openMode(GameMode mode) async {
    if (!await Lives.instance.ensure(context)) return;
    if (!mounted) return;
    Session.instance.selectedMode = mode;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StartPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    Notices.instance.register(context);
    final enabled = _enabledIds;
    final modes = enabled == null
        ? GameMode.values
        : GameMode.values.where((m) => enabled.contains(m.id)).toList();

    return Scaffold(
      body: Stack(
        children: [
          const PlainBackground(),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 8),
                // Üst çubuk: sıralama, ses, oyuncu adı.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      _TopChip(
                        key: const ValueKey('btn_leaderboard'),
                        icon: Icons.emoji_events_outlined,
                        label: 'SIRALAMA',
                        accent: AppTheme.gold,
                        onTap: _openLeaderboard,
                      ),
                      const SizedBox(width: 8),
                      const _LivesChip(),
                      const Spacer(),
                      _SoundChip(),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person_outline_rounded,
                              color: AppTheme.pitch, size: 14),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              Session.instance.displayName.toUpperCase(),
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.eyebrow
                                  .copyWith(color: AppTheme.pitch),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text('OYUN MODU SEÇ',
                          style: TextStyle(
                            color: AppTheme.text,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            height: 1.1,
                          )),
                      const SizedBox(height: 4),
                      const Text('Rakibinle aynı modda buluşun',
                          style: AppTheme.body),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                // Rakip gerektirmeyen iki giriş: kuyruk ve günlük tahta.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: _QuickTile(
                          icon: Icons.bolt_rounded,
                          label: 'HIZLI EŞLEŞ',
                          hint: 'Rastgele rakip',
                          colors: const [Color(0xFFFF6B4A), Color(0xFFFF6B4A)],
                          onTap: _openQuickMatch,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickTile(
                          icon: Icons.calendar_today_rounded,
                          label: 'GÜNÜN TAHTASI',
                          hint: 'Tek başına',
                          colors: const [AppTheme.pitch, AppTheme.pitch],
                          onTap: _openDaily,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
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
          color: expanded ? AppTheme.surfaceHigh : AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(
            color: expanded
                ? mode.colors.first.withOpacity(0.7)
                : AppTheme.borderStrong,
            width: 1,
          ),
          boxShadow: AppTheme.shadow,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: mode.colors.first.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                  ),
                  child: Icon(mode.icon, color: mode.colors.first, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mode.title,
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        mode.tagline,
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.textMuted,
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
                  Text(mode.description, style: AppTheme.body),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      key: ValueKey('play_${mode.id}'),
                      onTap: onPlay,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: mode.colors.first,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusSm),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.play_arrow_rounded,
                                color: _onAccent(mode.colors.first), size: 20),
                            const SizedBox(width: 6),
                            Text(
                              'BU MODU OYNA',
                              style: TextStyle(
                                color: _onAccent(mode.colors.first),
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.4,
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

/// Açık vurgu üstünde koyu, koyu vurgu üstünde beyaz yazı.
Color _onAccent(Color c) =>
    c.computeLuminance() > 0.35 ? AppTheme.bg : Colors.white;

/// Mod listesinin üstündeki kısayol kartı.
class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.hint,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = colors.first;
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: AppTheme.borderStrong),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Üst çubuktaki küçük yuvarlak etiket (sıralama, oyuncu adı).
class _TopChip extends StatelessWidget {
  const _TopChip({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.borderStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: accent, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kalan can: ♥ 7/10. Dokununca yenilenme süresi.
class _LivesChip extends StatelessWidget {
  const _LivesChip();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LivesStatus?>(
      valueListenable: Lives.instance.status,
      builder: (context, s, _) {
        if (s == null) return const SizedBox.shrink();
        final empty = s.lives == 0;
        return GestureDetector(
          key: const ValueKey('chip_lives'),
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(empty
                ? 'Canın bitti — ${s.resetsInText} sonra ${s.max} can yenilenir.'
                : '${s.lives}/${s.max} can · ${s.resetsInText} sonra yenilenir.'),
          )),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: empty
                    ? AppTheme.danger.withOpacity(0.6)
                    : AppTheme.borderStrong,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite_rounded,
                    color: empty ? AppTheme.danger : const Color(0xFFFF6B4A),
                    size: 15),
                const SizedBox(width: 5),
                Text(
                  '${s.lives}',
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Ses aç/kapa. Tercih cihazda saklanır.
class _SoundChip extends StatefulWidget {
  @override
  State<_SoundChip> createState() => _SoundChipState();
}

class _SoundChipState extends State<_SoundChip> {
  @override
  Widget build(BuildContext context) {
    final on = Sound.instance.enabled;
    return GestureDetector(
      key: const ValueKey('btn_sound'),
      onTap: () async {
        await Sound.instance.setEnabled(!on);
        if (!on) Sound.instance.play(Sfx.tap);
        if (mounted) setState(() {});
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.borderStrong),
        ),
        child: Icon(
          on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          color: on ? AppTheme.text : AppTheme.textFaint,
          size: 18,
        ),
      ),
    );
  }
}
