import 'package:flutter/material.dart';

import 'package:footttball/core/theme/app_theme.dart';

/// Uygulamanın koyu uzay temalı arka planı.
///
/// `Positioned.fill` yerine `SizedBox.expand` kullanılır: `Stack` varsayılan
/// olarak konumlandırılmamış çocuklarının boyutunu alır, dolayısıyla dar bir
/// içerik sütunu arka planı da daraltıyor ve ekranın kalanı boş kalıyordu.
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
    return SizedBox.expand(
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

/// Logosuz, düz zemin.
///
/// Lacivert katman üstünde çok soluk saha çizgileri (orta yuvarlak, orta
/// çizgi). Kimlik sahadan geliyor; renkli parlamalar ve gradyan lekeler
/// yok. `accent` moda özgü ince bir üst şerit çizer.
class PlainBackground extends StatelessWidget {
  const PlainBackground({super.key, this.accent});

  /// Moda özgü vurgu: ekranın üst kenarında 3 px'lik şerit.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppTheme.bgRaised, AppTheme.bg],
              ),
            ),
          ),
          const CustomPaint(painter: _PitchLinesPainter()),
          if (accent != null)
            Align(
              alignment: Alignment.topCenter,
              child: Container(height: 3, color: accent!.withOpacity(0.9)),
            ),
        ],
      ),
    );
  }
}

/// Zemindeki saha çizgileri: orta yuvarlak ve orta çizgi, %4 beyaz.
class _PitchLinesPainter extends CustomPainter {
  const _PitchLinesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final center = Offset(size.width / 2, size.height * 0.5);
    canvas.drawCircle(center, size.width * 0.34, paint);
    canvas.drawCircle(center, 3, paint..style = PaintingStyle.fill);
    paint.style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);
    // Kenar çizgileri
    final inset = 14.0;
    canvas.drawRect(
      Rect.fromLTRB(inset, -20, size.width - inset, size.height + 20),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Oyun ekranlarının kullandığı, içeriği öne çıkaran koyu arka plan.
class GameBackground extends StatelessWidget {
  const GameBackground({super.key, this.accent});

  final Color? accent;

  @override
  Widget build(BuildContext context) => PlainBackground(accent: accent);
}

/// Tiki Taka Toe tahtasının arka planı.
class BoardBackground extends StatelessWidget {
  const BoardBackground({super.key, this.dim = 0});

  final double dim;

  @override
  Widget build(BuildContext context) =>
      const PlainBackground(accent: Color(0xFF2575FC));
}

/// Kart: düz yüzey, ince kenarlık, üstte 2 px vurgu çizgisi.
///
/// Adı eski neon dönemden kalma; görünüm artık sakin. `colors.first` vurgu
/// çizgisinin rengi.
class NeonPanel extends StatelessWidget {
  const NeonPanel({
    super.key,
    required this.child,
    this.colors = const [AppTheme.pitch, AppTheme.pitch],
    this.padding = const EdgeInsets.all(20),
    this.radius = AppTheme.radiusLg,
  });

  final Widget child;
  final List<Color> colors;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppTheme.borderStrong),
        boxShadow: AppTheme.shadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 2, color: colors.first),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Başlık: düz, kalın, hafif aralıklı. Kontur ve gradyan yok.
///
/// `colors.last` altındaki kısa vurgu çizgisinin rengi.
class NeonTitle extends StatelessWidget {
  const NeonTitle(
    this.text, {
    super.key,
    this.fontSize = 22,
    this.colors = const [AppTheme.text, AppTheme.pitch],
  });

  final String text;
  final double fontSize;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: AppTheme.text,
            letterSpacing: 1.4,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 28,
          height: 3,
          decoration: BoxDecoration(
            color: colors.last,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

/// Sol üst geri düğmesi: düz yüzey, ince kenarlık.
class GlassBackButton extends StatelessWidget {
  const GlassBackButton({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppTheme.borderStrong),
        ),
        child: const Center(
          child: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: AppTheme.text),
        ),
      ),
    );
  }
}

/// Ana eylem düğmesi (START / JOIN / PLAY).
///
/// Düz dolgu, koyu yazı; parlama yok. `colors.first` dolgu rengi.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.colors = const [AppTheme.pitch, AppTheme.pitch],
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
    final fill = colors.first;
    // Açık dolguda koyu yazı, koyu dolguda beyaz.
    final fg = fill.computeLuminance() > 0.35 ? AppTheme.bg : Colors.white;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            alignment: Alignment.center,
            // Dar ekranlarda uzun etiketler ("OYUNU BAŞLAT") butonu
            // taşırıyordu; içerik sığmadığında orantılı olarak küçülür.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: fg, size: 20),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
