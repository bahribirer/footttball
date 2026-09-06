import 'package:flutter/material.dart';

/// Uygulamadaki oyun modları. `id` değerleri backend protokolüyle birebir aynıdır.
enum GameMode {
  tikiTakaToe(
    id: 'tiki_taka_toe',
    title: 'Tiki Taka Toe',
    tagline: '3x3 tahtada üç taş',
    description:
        'Kulüp ve millet kesişimine uyan futbolcuyu yaz, üç taşı ilk sen tamamla.',
    icon: Icons.grid_3x3_rounded,
    colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
  ),
  playerGuess(
    id: 'player_guess',
    title: 'Oyuncu Tahmin',
    tagline: 'Milli takım x kulüp',
    description:
        'Biriniz milli takımı, diğeriniz kulübü seçer. Eşleşmeye uyan futbolcuyu ilk bilen puanı alır.',
    icon: Icons.bolt_rounded,
    colors: [Color(0xFFFF512F), Color(0xFFDD2476)],
  ),
  lastLetter(
    id: 'last_letter',
    title: 'Son Harf',
    tagline: 'İsim zinciri',
    description:
        'Rakibinin yazdığı futbolcunun son harfiyle başlayan bir futbolcu yaz. Süresi ilk biten kaybeder.',
    icon: Icons.abc_rounded,
    colors: [Color(0xFF00F260), Color(0xFF0575E6)],
  ),
  categoryRace(
    id: 'category_race',
    title: 'Kategori Yarışı',
    tagline: 'Sırayla doğru isim',
    description:
        'Verilen kategoriye uyan futbolcuları sırayla yazın. Yanlış cevap süreden götürür.',
    icon: Icons.category_rounded,
    colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
  );

  const GameMode({
    required this.id,
    required this.title,
    required this.tagline,
    required this.description,
    required this.icon,
    required this.colors,
  });

  final String id;
  final String title;
  final String tagline;
  final String description;
  final IconData icon;
  final List<Color> colors;

  /// Lig seçimi yalnızca Tiki Taka Toe için anlamlı.
  bool get needsLeague => this == GameMode.tikiTakaToe;

  /// Kurucunun tur sayısı belirlediği modlar.
  bool get needsRoundCount =>
      this == GameMode.tikiTakaToe || this == GameMode.playerGuess;

  /// Satranç saatiyle oynanan modlar: oyuncu başına süre seçilir.
  bool get isClockBased =>
      this == GameMode.lastLetter || this == GameMode.categoryRace;

  /// Kurucunun kategoriyi seçtiği mod.
  bool get needsCategory => this == GameMode.categoryRace;

  /// Tur seçenekleri ve her birinin adı — oda kurma ekranında gösterilir.
  List<int> get roundOptions =>
      this == GameMode.tikiTakaToe ? const [1, 3, 5] : const [3, 5, 7];

  /// Saat seçenekleri (saniye).
  List<int> get clockOptions => const [30, 50, 80];

  /// Oyun mantığı sunucuda yürüyen modlar.
  bool get isServerDriven => this != GameMode.tikiTakaToe;

  static GameMode fromId(String? id) => GameMode.values.firstWhere(
        (mode) => mode.id == id,
        orElse: () => GameMode.tikiTakaToe,
      );
}
