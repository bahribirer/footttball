import 'package:flutter/material.dart';

import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/features/profile/name_screen.dart';
import 'package:footttball/shared/widgets/app_background.dart';

/// Oyunu tanıtan üç adımlık açılış turu.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;

  static const _steps = <_Step>[
    _Step(
      icon: Icons.sports_soccer_rounded,
      title: 'FUTBOL BİLGİNİ\nYARIŞTIR',
      text:
          'Arkadaşınla aynı odada buluş, dört farklı modda karşı karşıya gel. '
          'Kazanan futbolu daha iyi bilen olsun.',
      colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
    ),
    _Step(
      icon: Icons.grid_3x3_rounded,
      title: 'DÖRT FARKLI\nOYUN MODU',
      text:
          'Tiki Taka Toe, Oyuncu Tahmin, Son Harf ve Kategori Yarışı. '
          'Her mod farklı bir beceri istiyor.',
      colors: [Color(0xFFFF512F), Color(0xFFDD2476)],
    ),
    _Step(
      icon: Icons.bolt_rounded,
      title: 'SÜREYLE\nYARIŞ',
      text:
          'Saat işlerken doğru futbolcuyu bulmalısın. Yanlış cevap süreden '
          'götürür — hızlı ve dikkatli ol.',
      colors: [Color(0xFF00F260), Color(0xFF0575E6)],
    ),
  ];

  void _finish() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, animation, __) =>
            FadeTransition(opacity: animation, child: const NameRoom()),
      ),
    );
  }

  void _next() {
    if (_page == _steps.length - 1) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_page];
    final last = _page == _steps.length - 1;

    return Scaffold(
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            child: PlainBackground(
              key: ValueKey(_page),
              accent: step.colors.first,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _finish,
                    child: Text(
                      'Atla',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _steps.length,
                    onPageChanged: (value) => setState(() => _page = value),
                    itemBuilder: (context, index) => _StepView(step: _steps[index]),
                  ),
                ),
                if (_page == 1) const _ModeStrip(),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _steps.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 7,
                      width: _page == index ? 26 : 7,
                      decoration: BoxDecoration(
                        color: _page == index
                            ? step.colors.last
                            : Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: SizedBox(
                    width: double.infinity,
                    child: PrimaryButton(
                      label: last ? 'HADİ BAŞLAYALIM' : 'DEVAM',
                      icon: last ? Icons.play_arrow_rounded : Icons.arrow_forward_rounded,
                      colors: step.colors,
                      onTap: _next,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step {
  const _Step({
    required this.icon,
    required this.title,
    required this.text,
    required this.colors,
  });

  final IconData icon;
  final String title;
  final String text;
  final List<Color> colors;
}

class _StepView extends StatelessWidget {
  const _StepView({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              width: 118,
              height: 118,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: step.colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white.withOpacity(0.2), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: step.colors.last.withOpacity(0.4),
                    blurRadius: 42,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(step.icon, color: Colors.white, size: 56),
            ),
          ),
          const SizedBox(height: 38),
          NeonTitle(step.title, fontSize: 25, colors: [Colors.white, step.colors.last]),
          const SizedBox(height: 18),
          Text(
            step.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.66),
              fontSize: 14.5,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

/// İkinci adımda dört modun kısa listesi.
class _ModeStrip extends StatelessWidget {
  const _ModeStrip();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: GameMode.values.map((mode) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: mode.colors.last.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: mode.colors.last.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(mode.icon, color: mode.colors.last, size: 14),
                const SizedBox(width: 7),
                Text(
                  mode.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
