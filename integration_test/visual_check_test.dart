// Görsel doğrulama yardımcısı: her oyun ekranını birkaç saniye açık tutar,
// böylece dışarıdan ekran görüntüsü alınabilir. Sürekli çalıştırılması
// gerekmez; arayüz değişikliklerinden sonra elle kontrol içindir.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:footttball/core/config/app_config.dart';
import 'package:footttball/core/session.dart';
import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/services/game_socket.dart';
import 'package:footttball/features/lobby/create_room_screen.dart';
import 'package:footttball/features/lobby/start_page.dart';
import 'package:footttball/features/lobby/waiting_room_screen.dart';
import 'package:footttball/features/modes/mode_select_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpFor(WidgetTester tester, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpUntil(WidgetTester tester, Finder f,
      {Duration timeout = const Duration(seconds: 25)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 120));
      if (f.evaluate().isNotEmpty) return;
    }
    fail('görünmedi: $f');
  }

  Future<void> showMode(WidgetTester tester, GameMode mode,
      {String? league,
      void Function(WebSocketChannel rival)? rivalScript}) async {
    Session.instance.playerName = 'Bahri';
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const ModeSelectScreen(),
    ));
    await pumpUntil(tester, find.text('OYUN MODU SEÇ'));
    await pumpFor(tester, const Duration(seconds: 3)); // menü görüntüsü

    await tester.tap(find.byKey(ValueKey('mode_card_${mode.id}')));
    await pumpFor(tester, const Duration(seconds: 3)); // açılmış kart

    await tester.tap(find.byKey(ValueKey('play_${mode.id}')));
    await pumpUntil(tester, find.byType(StartPage));
    await pumpFor(tester, const Duration(seconds: 2));

    await tester.tap(find.byKey(const ValueKey('btn_create_room')));
    await pumpUntil(tester, find.byType(CreateRoomScreen));
    await pumpUntil(tester, find.text('ODA KODU'));
    await pumpFor(tester, const Duration(seconds: 3)); // oda kurma ekranı

    final code = find
        .descendant(
            of: find.byKey(const ValueKey('room_code')),
            matching: find.byType(Text))
        .evaluate()
        .map((e) => (e.widget as Text).data ?? '')
        .where((t) => t.length == 1 && int.tryParse(t) != null)
        .join();

    if (league != null) {
      await tester.tap(find.byKey(ValueKey('league_$league')));
      await pumpFor(tester, const Duration(seconds: 2));
    }

    if (league != null) {
      await pumpUntil(tester, find.text('SERİ UZUNLUĞU'));
      await pumpFor(tester, const Duration(seconds: 2));
      await tester.ensureVisible(find.byKey(const ValueKey('rounds_3')));
      await tester.tap(find.byKey(const ValueKey('rounds_3')));
      await pumpFor(tester, const Duration(milliseconds: 500));
    }

    await tester.ensureVisible(find.byKey(const ValueKey('btn_play')));
    await tester.tap(find.byKey(const ValueKey('btn_play')));

    await pumpUntil(tester, find.byType(WaitingRoomScreen));
    await pumpFor(tester, const Duration(seconds: 3)); // bekleme odası

    final rival = WebSocketChannel.connect(Uri.parse(
        '${AppConfig.wsBase}/ws/v2/$code?name=Rakip&mode=${mode.id}'));
    await rival.ready;

    await pumpFor(tester, const Duration(seconds: 4)); // VS ekranı
    rivalScript?.call(rival);
    await pumpFor(tester, const Duration(seconds: 12)); // oyun ekranı

    await rival.sink.close();
    await GameSocket.instance.disconnect();
  }

  testWidgets('görsel: Son Harf', (t) async {
    await showMode(t, GameMode.lastLetter, rivalScript: (rival) {
      rival.sink.add(jsonEncode(
          {'type': 'action', 'action': 'answer', 'value': 'Erling Haaland'}));
    });
  });

  testWidgets('görsel: Kategori Yarışı', (t) async {
    await showMode(t, GameMode.categoryRace);
  });

  testWidgets('görsel: Oyuncu Tahmin', (t) async {
    await showMode(t, GameMode.playerGuess);
  });

  testWidgets('görsel: Tiki Taka Toe', (t) async {
    await showMode(t, GameMode.tikiTakaToe, league: 'Premier League');
  });
}
