import 'package:flutter/material.dart';

/// Uygulamanın koyu uzay temalı arka planı.
///
/// Arka plan görselinde büyük bir logo bulunduğu için, üzerine içerik gelen
/// ekranlarda [dim] ile karartma katmanı uygulanır; aksi halde yazılar
/// logonun üstüne binip okunmaz hale geliyor.
class AppBackground extends StatelessWidget {
  const AppBackground({
    super.key,
    this.asset = 'images/arka2.PNG',
    this.dim = 0,
  });

  final String asset;
  final double dim;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(asset, fit: BoxFit.cover),
          if (dim > 0)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0B0B18).withOpacity(dim + 0.12),
                    const Color(0xFF0B0B18).withOpacity(dim),
                    const Color(0xFF0B0B18).withOpacity(dim + 0.08),
                  ],
                  stops: const [0, 0.55, 1],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Oyun ekranlarının kullandığı, içeriği öne çıkaran koyu arka plan.
class GameBackground extends StatelessWidget {
  const GameBackground({super.key});

  @override
  Widget build(BuildContext context) =>
      const AppBackground(asset: 'images/arka2.PNG', dim: 0.62);
}

/// Tiki Taka Toe tahtasının kullandığı açık arka plan.
class BoardBackground extends StatelessWidget {
  const BoardBackground({super.key, this.dim = 0});

  final double dim;

  @override
  Widget build(BuildContext context) =>
      AppBackground(asset: 'images/arka1.png', dim: dim);
}

/// Neon çerçeveli koyu panel — diyaloglarda ve kartlarda ortak görünüm.
class NeonPanel extends StatelessWidget {
  const NeonPanel({
    super.key,
    required this.child,
    this.colors = const [Colors.cyanAccent, Colors.purpleAccent],
    this.padding = const EdgeInsets.all(20),
    this.radius = 22,
  });

  final Widget child;
  final List<Color> colors;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.last.withOpacity(0.35),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: const Color(0xFF14142A),
          borderRadius: BorderRadius.circular(radius - 2.5),
        ),
        child: child,
      ),
    );
  }
}

/// Kenarlığı çizili, içi gradyan dolgulu başlık yazısı.
class NeonTitle extends StatelessWidget {
  const NeonTitle(
    this.text, {
    super.key,
    this.fontSize = 22,
    this.colors = const [Colors.white, Colors.cyanAccent],
  });

  final String text;
  final double fontSize;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5
              ..color = colors.last.withOpacity(0.45),
          ),
        ),
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: colors,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(bounds),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// Ekranların sol üstündeki cam görünümlü geri düğmesi.
class GlassBackButton extends StatelessWidget {
  const GlassBackButton({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
      child: Container(
        width: 45,
        height: 45,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(0.2),
              Colors.white.withOpacity(0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

/// Ana eylem düğmesi (START / JOIN / PLAY).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.colors = const [Color(0xFF6A11CB), Color(0xFF2575FC)],
    this.enabled = true,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final List<Color> colors;
  final bool enabled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: colors.first.withOpacity(0.5),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 10),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
