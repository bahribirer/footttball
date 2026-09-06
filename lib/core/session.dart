import 'package:footttball/data/models/game_mode.dart';

/// Uygulama boyunca yaşayan oturum bilgisi.
///
/// Eski `globals.dart` yerine geçer; serbest değişkenler yerine tek bir
/// nesnede toplanmıştır.
class Session {
  Session._();
  static final Session instance = Session._();

  /// Oyuncunun isim ekranında girdiği ad.
  String playerName = '';

  /// Menüde seçilen oyun modu.
  GameMode selectedMode = GameMode.tikiTakaToe;

  /// Tiki Taka Toe için seçilen lig kodu (GB1, TR1, RANDOM ...).
  String leagueId = 'RANDOM';

  /// Seri uzunluğu / tur sayısı.
  int roundCount = 1;

  /// Saat tabanlı modlarda oyuncu başına süre (saniye).
  int clockSeconds = 50;

  /// Kategori Yarışı'nda kurucunun seçtiği kategori; boşsa sunucu rastgele seçer.
  String? categoryId;

  bool get hasName => playerName.trim().isNotEmpty;

  String get displayName => hasName ? playerName.trim() : 'Oyuncu';
}
