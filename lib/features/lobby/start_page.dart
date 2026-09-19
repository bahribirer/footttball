import 'package:flutter/material.dart';

import 'package:footttball/core/theme/app_theme.dart';

import 'package:footttball/core/session.dart';
import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/features/lobby/create_room_screen.dart';
import 'package:footttball/features/lobby/join_room_screen.dart';
import 'package:footttball/shared/widgets/app_background.dart';

/// Seçilen mod için oda kur / odaya katıl ekranı.
class StartPage extends StatefulWidget {
  const StartPage({super.key});

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _glow;

  GameMode get _mode => Session.instance.selectedMode;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _intro.dispose();
    _glow.dispose();
    super.dispose();
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PlainBackground(accent: _mode.colors.first),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      GlassBackButton(
                          onTap: () => Navigator.of(context).maybePop()),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
                    child: Column(
                      children: [
                        _buildModeHero(),
                        const SizedBox(height: 30),
                        _slideIn(
                          0,
                          _ActionCard(
                            key: const ValueKey('btn_create_room'),
                            title: 'ODA KUR',
                            subtitle: 'Kodu sen al, arkadaşını çağır',
                            icon: Icons.add_circle_outline_rounded,
                            colors: _mode.colors,
                            glow: _glow,
                            onTap: () => _open(const CreateRoomScreen()),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _slideIn(
                          1,
                          _ActionCard(
                            key: const ValueKey('btn_join_room'),
                            title: 'ODAYA KATIL',
                            subtitle: 'Sana verilen kodu gir',
                            icon: Icons.login_rounded,
                            colors: _mode.colors,
                            borderColor: _mode.colors.first,
                            glow: _glow,
                            onTap: () => _open(const JoinRoomScreen()),
                          ),
                        ),
                        const SizedBox(height: 26),
                        _slideIn(2, _HintRow(accent: _mode.colors.last)),
                      ],
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

  /// Kartların sırayla aşağıdan gelmesi.
  Widget _slideIn(int order, Widget child) {
    final animation = CurvedAnimation(
      parent: _intro,
      curve: Interval(0.15 * order, 1, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Opacity(
        opacity: animation.value.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 28 * (1 - animation.value)),
          child: child,
        ),
      ),
    );
  }

  Widget _buildModeHero() {
    final accent = _mode.colors.first;
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.14),
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: accent.withOpacity(0.5)),
          ),
          child: Icon(_mode.icon, color: accent, size: 40),
        ),
        const SizedBox(height: 18),
        NeonTitle(
          _mode.title.toUpperCase(),
          fontSize: 24,
          colors: [AppTheme.text, accent],
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            _mode.description,
            textAlign: TextAlign.center,
            style: AppTheme.body,
          ),
        ),
      ],
    );
  }
}

/// Büyük eylem kartı (oda kur / katıl).
class _ActionCard extends StatefulWidget {
  const _ActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.glow,
    required this.onTap,
    this.borderColor,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final Color? borderColor;
  final AnimationController glow;
  final VoidCallback onTap;

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // Birincil kart dolu (mod rengi), ikincil kart yüzey renginde.
    final primary = widget.borderColor == null;
    final accent = primary ? widget.colors.first : widget.borderColor!;
    final fg = primary ? _onAccent(accent) : AppTheme.text;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          decoration: BoxDecoration(
            color: primary ? accent : AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(
                color: primary ? Colors.transparent : AppTheme.borderStrong),
            boxShadow: AppTheme.shadow,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: primary
                      ? Colors.black.withOpacity(0.14)
                      : accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                ),
                child:
                    Icon(widget.icon, color: primary ? fg : accent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: fg,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        color:
                            primary ? fg.withOpacity(0.75) : AppTheme.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  color: primary ? fg.withOpacity(0.8) : AppTheme.textMuted,
                  size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

Color _onAccent(Color c) =>
    c.computeLuminance() > 0.35 ? AppTheme.bg : Colors.white;

class _HintRow extends StatelessWidget {
  const _HintRow({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(Icons.groups_rounded, color: accent, size: 19),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'İki kişilik oyun: biriniz oda kurar, diğeriniz o kodla katılır.',
              style: AppTheme.body,
            ),
          ),
        ],
      ),
    );
  }
}
