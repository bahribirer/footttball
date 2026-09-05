// Lobi ekranlarını uzun süre açık tutar; dışarıdan ekran görüntüsü almak için.
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

  testWidgets('lobi ekranları', (t) async {
    Session.instance.playerName = 'Bahri';
    await t.pumpWidget(const MaterialApp(
        debugShowCheckedModeBanner: false, home: ModeSelectScreen()));
    await waitFor(t, find.text('OYUN MODU SEÇ'));

    await t.tap(find.byKey(const ValueKey('mode_card_tiki_taka_toe')));
    await hold(t, const Duration(seconds: 6));   // [1] açılmış mod kartı

    await t.tap(find.byKey(const ValueKey('play_tiki_taka_toe')));
    await waitFor(t, find.byType(StartPage));
    await hold(t, const Duration(seconds: 6));   // [2] oda kur / katıl

    await t.tap(find.byKey(const ValueKey('btn_create_room')));
    await waitFor(t, find.byType(CreateRoomScreen));
    await waitFor(t, find.text('ODA KODU'));
    await hold(t, const Duration(seconds: 8));   // [3] oda kurma + lig listesi

    final code = find
        .descendant(of: find.byType(CreateRoomScreen), matching: find.byType(Text))
        .evaluate()
        .map((e) => (e.widget as Text).data ?? '')
        .where((s) => s.length == 1 && int.tryParse(s) != null)
        .join();

    await t.tap(find.byKey(const ValueKey('league_Premier League')));
    await hold(t, const Duration(seconds: 3));
    await t.tap(find.byKey(const ValueKey('btn_play')));
    await waitFor(t, find.text('SERİ UZUNLUĞU'));
    await hold(t, const Duration(seconds: 6));   // [4] seri seçimi

    await t.tap(find.byKey(const ValueKey('rounds_3')));
    await waitFor(t, find.byType(WaitingRoomScreen));
    await hold(t, const Duration(seconds: 8));   // [5] bekleme odası (tek kişi)

    final rival = WebSocketChannel.connect(Uri.parse(
        '${AppConfig.wsBase}/ws/v2/$code?name=Rakip&mode=tiki_taka_toe'));
    await rival.ready;
    await hold(t, const Duration(seconds: 10));  // [6] VS ekranı + oyuna geçiş
    await hold(t, const Duration(seconds: 8));   // [7] oyun tahtası

    await rival.sink.close();
    await GameSocket.instance.disconnect();
  });
}
