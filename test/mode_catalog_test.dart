import 'package:flutter_test/flutter_test.dart';

import 'package:footttball/data/models/game_mode.dart';

/// Mod kataloğu istemci tarafı sözleşmesi.
///
/// Sunucu tarafında `tests/test_mode_registry.py` aynı id'leri karşılaştırıyor;
/// buradakiler uygulamanın kendi içindeki tutarlılığı koruyor.
void main() {
  test('mod kimlikleri benzersiz ve protokol biçiminde', () {
    final ids = GameMode.values.map((m) => m.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'yinelenen mod kimliği var');
    for (final id in ids) {
      expect(
        RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id),
        isTrue,
        reason: '$id protokol biçimine uymuyor (küçük harf ve alt çizgi)',
      );
    }
  });

  test('her modun görünür metinleri dolu', () {
    for (final mode in GameMode.values) {
      expect(mode.title, isNotEmpty, reason: '${mode.id} başlıksız');
      expect(mode.tagline, isNotEmpty, reason: '${mode.id} sloganısız');
      expect(mode.description, isNotEmpty, reason: '${mode.id} açıklamasız');
      expect(mode.colors.length, greaterThanOrEqualTo(2),
          reason: '${mode.id} için gradyan iki renk ister');
    }
  });

  test('iskelet üretecinin bıraktığı yer tutucular kalmamış', () {
    // new_mode.py 'TODO:' metinleriyle iskelet üretiyor; yayına çıkan bir
    // modda bunların kalması kullanıcıya görünür.
    for (final mode in GameMode.values) {
      expect(mode.tagline.contains('TODO'), isFalse,
          reason: '${mode.id} sloganı hâlâ yer tutucu');
      expect(mode.description.contains('TODO'), isFalse,
          reason: '${mode.id} açıklaması hâlâ yer tutucu');
    }
  });

  test('fromId bilinmeyen değeri güvenli karşılıyor', () {
    // Sunucu ileride yeni bir mod eklerse eski uygulama bunu görebilir;
    // çökmek yerine varsayılana düşmeli.
    expect(() => GameMode.fromId('bilinmeyen_mod'), returnsNormally);
    expect(() => GameMode.fromId(null), returnsNormally);
  });
}
