import 'package:flutter/material.dart';

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
                      GlassBackButton(onTap: () => Navigator.of(context).maybePop()),
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
                            colors: const [Color(0xFF1F1B3A), Color(0xFF2C2652)],
                            borderColor: _mode.colors.last,
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
    return Column(
      children: [
        AnimatedBuilder(
          animation: _glow,
          builder: (context, child) => Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _mode.colors.last.withOpacity(0.22 + 0.18 * _glow.value),
                  blurRadius: 38 + 16 * _glow.value,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: child,
          ),
          child: Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: _mode.colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: Colors.white.withOpacity(0.22), width: 2),
            ),
            child: Icon(_mode.icon, color: Colors.white, size: 44),
          ),
        ),
        const SizedBox(height: 18),
        NeonTitle(
          _mode.title.toUpperCase(),
          fontSize: 26,
          colors: [Colors.white, _mode.colors.last],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            _mode.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.62),
              fontSize: 13.5,
              height: 1.45,
            ),
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
    final border = widget.borderColor ?? Colors.white.withOpacity(0.22);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedBuilder(
          animation: widget.glow,
          builder: (context, child) => Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: widget.colors.last.withOpacity(0.2 + 0.14 * widget.glow.value),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: child,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: widget.colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: border, width: 1.6),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.28),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.16)),
                  ),
                  child: Icon(widget.icon, color: Colors.white, size: 27),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.white.withOpacity(0.65), size: 17),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// İki oyuncunun aynı kodda buluşması gerektiğini anlatan ipucu.
class _HintRow extends StatelessWidget {
  const _HintRow({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Row(
        children: [
          Icon(Icons.groups_rounded, color: accent.withOpacity(0.85), size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'İki kişilik oyun: biriniz oda kurar, diğeriniz o kodla katılır.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
