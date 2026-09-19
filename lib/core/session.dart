import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

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

  /// Cihaza bağlı kalıcı kimlik; skor tablosu bu kimlikle puan tutar.
  ///
  /// Hesap sistemi yok: ilk açılışta üretilir, `shared_preferences`'ta
  /// saklanır. Uygulama silinirse puanlar yeni bir kimlikle sıfırdan başlar.
  String playerId = '';

  static const _idKey = 'player_id';

  /// Kimliği yükler ya da ilk kez üretir. Başlangıçta bir kez çağrılır;
  /// depolama okunamazsa oturumluk bir kimlik kullanılır.
  Future<void> ensurePlayerId() async {
    if (playerId.isNotEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_idKey);
      if (saved != null && saved.length >= 8) {
        playerId = saved;
        return;
      }
      playerId = _newId();
      await prefs.setString(_idKey, playerId);
    } catch (_) {
      playerId = _newId();
    }
  }

  static String _newId() {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(24, (_) => alphabet[rng.nextInt(alphabet.length)])
        .join();
  }

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
