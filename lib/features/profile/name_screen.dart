import 'dart:async';

import 'package:flutter/material.dart';

import 'package:footttball/core/session.dart';
import 'package:footttball/features/modes/mode_select_screen.dart';
import 'package:footttball/shared/widgets/app_background.dart';

/// Oyuncunun adını girdiği açılış ekranı.
class NameRoom extends StatefulWidget {
  const NameRoom({super.key});

  @override
  State<NameRoom> createState() => _NameRoomState();
}

class _NameRoomState extends State<NameRoom> with TickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  late final AnimationController _intro;
  late final AnimationController _glow;

  bool _loading = false;

  bool get _valid => _controller.text.trim().length >= 2;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _intro.dispose();
    _glow.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_valid) {
      _focus.requestFocus();
      return;
    }

    setState(() => _loading = true);
    Session.instance.playerName = _controller.text.trim();

    Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 420),
          pageBuilder: (_, animation, __) => FadeTransition(
            opacity: animation,
            child: const ModeSelectScreen(),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    const accent = Colors.cyanAccent;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const PlainBackground(accent: Color(0xFF6A11CB)),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height * 0.82,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _fade(0, _buildBadge(accent)),
                    const SizedBox(height: 26),
                    _fade(1, const NeonTitle('TIKI TAKA TOE', fontSize: 30)),
                    const SizedBox(height: 10),
                    _fade(
                      2,
                      Text(
                        'Futbol bilgini arkadaşınla yarıştır',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    _fade(3, _buildField(accent)),
                    const SizedBox(height: 12),
                    _fade(4, _buildHint()),
                    const SizedBox(height: 34),
                    _fade(
                      5,
                      _loading
                          ? const _LoadingBall()
                          : PrimaryButton(
                              label: 'BAŞLA',
                              icon: Icons.sports_soccer_rounded,
                              enabled: _valid,
                              onTap: _continue,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fade(int order, Widget child) {
    final animation = CurvedAnimation(
      parent: _intro,
      curve:
          Interval((order * 0.1).clamp(0, 0.6), 1, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Opacity(
        opacity: animation.value.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 22 * (1 - animation.value)),
          child: child,
        ),
      ),
    );
  }

  Widget _buildBadge(Color accent) {
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.18 + 0.16 * _glow.value),
              blurRadius: 40 + 16 * _glow.value,
              spreadRadius: 2,
            ),
          ],
        ),
        child: child,
      ),
      child: Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 2),
        ),
        child: const Icon(Icons.sports_soccer_rounded,
            color: Colors.white, size: 52),
      ),
    );
  }

  Widget _buildField(Color accent) {
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: (_valid ? accent : Colors.white24)
                  .withOpacity(0.12 + 0.14 * _glow.value),
              blurRadius: 22,
              spreadRadius: 1,
            ),
          ],
        ),
        child: child,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.42),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _valid ? accent.withOpacity(0.8) : Colors.white24,
            width: 1.8,
          ),
        ),
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.words,
          maxLength: 14,
          onSubmitted: (_) => _continue(),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 1.6,
          ),
          cursorColor: accent,
          decoration: InputDecoration(
            counterText: '',
            hintText: 'ADIN',
            hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.28),
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
            prefixIcon: Icon(Icons.person_rounded, color: accent, size: 24),
          ),
        ),
      ),
    );
  }

  Widget _buildHint() {
    final text = _controller.text.trim().isEmpty
        ? 'Rakibin bu ismi görecek'
        : (_valid ? 'Hazırsın!' : 'En az 2 harf gir');
    final color = _valid ? Colors.greenAccent : Colors.white38;

    return Text(
      text,
      style:
          TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
    );
  }
}

/// Geçiş sırasında dönen top.
class _LoadingBall extends StatefulWidget {
  const _LoadingBall();

  @override
  State<_LoadingBall> createState() => _LoadingBallState();
}

class _LoadingBallState extends State<_LoadingBall>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RotationTransition(
          turns: _spin,
          child: const Icon(Icons.sports_soccer_rounded,
              color: Colors.white, size: 44),
        ),
        const SizedBox(height: 14),
        Text(
          'SAHAYA ÇIKILIYOR...',
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }
}
