// Öneri listesinin davranışı.
//
// İki kural doğrulanır:
//   * Son Harf'te öneri çıkmaz — modun özü futbolcuyu hatırlamak.
//   * Öneri açılıp kapanırken giriş alanı yerinden oynamaz. Liste eskiden
//     giriş alanının kardeşiydi ve her aramada ekran zıplıyordu.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:footttball/core/config/app_config.dart';
import 'package:footttball/core/session.dart';
import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/services/game_socket.dart';
import 'package:footttball/features/games/category_race/category_race_screen.dart';
import 'package:footttball/features/games/last_letter/last_letter_screen.dart';
import 'package:footttball/features/lobby/create_room_screen.dart';
import 'package:footttball/features/lobby/start_page.dart';
import 'package:footttball/features/lobby/waiting_room_screen.dart';
import 'package:footttball/features/modes/mode_select_screen.dart';
import 'package:footttball/shared/widgets/player_suggestion_field.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> hold(WidgetTester t, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> waitFor(WidgetTester t, Finder f,
      {Duration timeout = const Duration(seconds: 30), String? label}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 120));
      if (f.evaluate().isNotEmpty) return;
    }
    fail('görünmedi: ${label ?? f.toString()}');
  }

  /// Seçilen modda oyunu başlatır ve sahte rakibin bağlantısını döndürür.
  Future<WebSocketChannel> startGame(WidgetTester t, GameMode mode) async {
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

    await t.tap(find.byKey(const ValueKey('btn_create_room')));
    await waitFor(t, find.byType(CreateRoomScreen));
    await waitFor(t, find.text('ODA KODU'));

    final code = find
        .descendant(
            of: find.byKey(const ValueKey('room_code')),
            matching: find.byType(Text))
        .evaluate()
        .map((e) => (e.widget as Text).data ?? '')
        .where((s) => s.length == 1 && int.tryParse(s) != null)
        .join();

    await t.ensureVisible(find.byKey(const ValueKey('btn_play')));
    await t.tap(find.byKey(const ValueKey('btn_play')));
    await waitFor(t, find.byType(WaitingRoomScreen));

    final rival = WebSocketChannel.connect(Uri.parse(
        '${AppConfig.wsBase}/ws/v2/$code?name=Rakip&mode=${mode.id}'));
    await rival.ready;
    return rival;
  }

  tearDown(() async {
    await GameSocket.instance.disconnect();
    GameSocket.instance.clearCallbacks();
    Session.instance
      ..playerName = ''
      ..selectedMode = GameMode.tikiTakaToe
      ..categoryId = null;
  });

  testWidgets('Son Harf: yazdıkça öneri çıkmaz', (t) async {
    final rival = await startGame(t, GameMode.lastLetter);
    await waitFor(t, find.byType(LastLetterScreen), label: 'Son Harf ekranı');
    await hold(t, const Duration(seconds: 3));

    await t.enterText(find.byType(TextField).first, 'haal');
    await hold(t, const Duration(seconds: 4));

    expect(find.textContaining('Haaland'), findsNothing,
        reason: 'Son Harf modunda öneri gösterilmemeli');

    await rival.sink.close();
  });

  testWidgets('Kategori Yarışı: öneri açılırken giriş alanı yerinden oynamaz',
      (t) async {
    final rival = await startGame(t, GameMode.categoryRace);
    await waitFor(t, find.byType(CategoryRaceScreen),
        label: 'Kategori Yarışı ekranı');
    await hold(t, const Duration(seconds: 3));

    expect(find.byType(PlayerSuggestionField), findsOneWidget);

    final field = find.byType(TextField).first;
    final before = t.getTopLeft(field);

    await t.enterText(field, 'haal');
    await hold(t, const Duration(seconds: 4));

    // Öneriler açıldı; giriş alanı aynı yerde kalmalı.
    expect(find.textContaining('Haaland'), findsWidgets,
        reason: 'öneri listesi açılmalı');
    expect(t.getTopLeft(field), before,
        reason: 'öneriler açılınca giriş alanı kaymamalı');

    // Liste kapanınca da yerinden oynamamalı.
    await t.enterText(field, '');
    await hold(t, const Duration(seconds: 2));
    expect(t.getTopLeft(field), before,
        reason: 'öneriler kapanınca giriş alanı kaymamalı');

    await rival.sink.close();
  });
}
