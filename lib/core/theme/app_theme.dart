import 'package:flutter/material.dart';

/// Tasarım belirteçleri.
///
/// Tek palet, tek yarıçap ölçeği, tek boşluk ölçeği. Ekranlar renk
/// uydurmaz; buradan alır. Zemin lacivert, vurgu çim yeşili, ikinci vurgu
/// altın — futbol kimliği neon parlamayla değil, sahanın renkleriyle.
abstract final class AppTheme {
  // Zemin katmanları (koyudan açığa)
  static const Color bg = Color(0xFF0B1020);
  static const Color bgRaised = Color(0xFF0F172A);
  static const Color surface = Color(0xFF141C33);
  static const Color surfaceHigh = Color(0xFF1B2540);

  // Çizgiler
  static const Color border = Color(0x14FFFFFF); // %8 beyaz
  static const Color borderStrong = Color(0x29FFFFFF); // %16 beyaz

  // Yazı
  static const Color text = Color(0xFFF3F5F9);
  static const Color textMuted = Color(0xFF9AA3B8);
  static const Color textFaint = Color(0xFF5F6B85);

  // Vurgular
  static const Color pitch = Color(0xFF22C55E); // çim yeşili
  static const Color gold = Color(0xFFF5B301);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF38BDF8);

  // Ölçekler
  static const double radiusSm = 10;
  static const double radius = 14;
  static const double radiusLg = 18;

  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;

  /// Bölüm başlığı: küçük, aralıklı, soluk. Neon başlıkların yerine.
  static const TextStyle eyebrow = TextStyle(
    color: textMuted,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.2,
  );

  static const TextStyle title = TextStyle(
    color: text,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.2,
    height: 1.15,
  );

  static const TextStyle body = TextStyle(
    color: textMuted,
    fontSize: 13.5,
    height: 1.45,
  );

  static const TextStyle label = TextStyle(
    color: text,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
  );

  /// Kart gölgesi: düşük, yumuşak; parlama yok.
  static const List<BoxShadow> shadow = [
    BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 6)),
  ];

  static ThemeData material() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: pitch,
          secondary: gold,
          surface: surface,
          error: danger,
          onPrimary: bg,
          onSurface: text,
        ),
        fontFamily: 'Roboto',
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: text),
          bodySmall: TextStyle(color: textMuted),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: surfaceHigh,
          contentTextStyle: const TextStyle(color: text),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: const BorderSide(color: borderStrong),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        dividerColor: border,
        splashFactory: InkSparkle.splashFactory,
      );
}
