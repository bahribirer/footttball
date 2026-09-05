// Oda kurma ekranının görsel turu.
//
// Ekranı her mod için açar ve ekran görüntüsü alınabilsin diye bir süre
// bekletir. Otomatik bir doğrulama yapmaz; yeni ayar bölümlerinin (lig,
// kategori, tur sayısı, süre) cihazda nasıl göründüğünü incelemek içindir.
//
//   flutter test integration_test/setup_visual_test.dart -d <cihaz> \
//     --dart-define=API_BASE=https://tikitakatoe.com \
//     --dart-define=WS_BASE=wss://tikitakatoe.com

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:footttball/core/session.dart';
import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/features/lobby/create_room_screen.dart';
import 'package:footttball/features/lobby/start_page.dart';
import 'package:footttball/features/modes/mode_select_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> hold(WidgetTester t, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> waitFor(WidgetTester t, Finder f,
      {Duration timeout = const Duration(seconds: 25)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 120));
      if (f.evaluate().isNotEmpty) return;
    }
    fail('görünmedi: $f');
  }

  for (final mode in GameMode.values) {
    testWidgets('oda kurma ekranı — ${mode.title}', (t) async {
      Session.instance
        ..playerName = 'Bahri'
        ..selectedMode = mode;

      await t.pumpWidget(const MaterialApp(
          debugShowCheckedModeBanner: false, home: ModeSelectScreen()));
      await waitFor(t, find.text('OYUN MODU SEÇ'));

      await t.tap(find.byKey(ValueKey('mode_card_${mode.id}')));
      await hold(t, const Duration(milliseconds: 600));
      await t.tap(find.byKey(ValueKey('play_${mode.id}')));
      await waitFor(t, find.byType(StartPage));
      await hold(t, const Duration(seconds: 2));

      await t.tap(find.byKey(const ValueKey('btn_create_room')));
      await waitFor(t, find.byType(CreateRoomScreen));
      await waitFor(t, find.text('ODA KODU'));

      // Ayar bölümleri yüklenirken ekran görüntüsü alınabilsin diye beklenir.
      await hold(t, const Duration(seconds: 9));

      // Ekranın alt yarısı (tur sayısı / süre) da görülsün.
      await t.drag(find.byType(CreateRoomScreen), const Offset(0, -320));
      await hold(t, const Duration(seconds: 8));
    });
  }
}
