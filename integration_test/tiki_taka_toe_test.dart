// Tiki Taka Toe oyun mantığı testleri.
//
// Tahta ve sıra devri istemcide işlendiği için hamleler sunucudan geri
// döndüğünde uygulanır. Test, hamleleri doğrudan aktarım kanalına yazarak
// bu döngüyü uçtan uca doğrular.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:footttball/core/config/app_config.dart';
import 'package:footttball/core/session.dart';
import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/services/game_socket.dart';
import 'package:footttball/features/games/tiki_taka_toe/tiki_taka_toe_screen.dart';
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
      {Duration timeout = const Duration(seconds: 30), String? label}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 120));
      if (f.evaluate().isNotEmpty) return;
    }
    fail('görünmedi: ${label ?? f.toString()}');
  }

  /// Oyunu başlatır ve sahte rakibin bağlantısını döndürür.
  Future<WebSocketChannel> startGame(WidgetTester t) async {
    Session.instance
      ..playerName = 'Bahri'
      ..selectedMode = GameMode.tikiTakaToe;

    await t.pumpWidget(const MaterialApp(
        debugShowCheckedModeBanner: false, home: ModeSelectScreen()));
    await waitFor(t, find.text('OYUN MODU SEÇ'));

    await t.tap(find.byKey(const ValueKey('mode_card_tiki_taka_toe')));
    await hold(t, const Duration(milliseconds: 500));
    await t.tap(find.byKey(const ValueKey('play_tiki_taka_toe')));
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

    await t.tap(find.byKey(const ValueKey('league_Premier League')));
    await hold(t, const Duration(milliseconds: 400));
    await waitFor(t, find.text('SERİ UZUNLUĞU'));
    await t.ensureVisible(find.byKey(const ValueKey('rounds_1')));
    await t.tap(find.byKey(const ValueKey('rounds_1')));
    await hold(t, const Duration(milliseconds: 300));
    await t.ensureVisible(find.byKey(const ValueKey('btn_play')));
    await t.tap(find.byKey(const ValueKey('btn_play')));
    await waitFor(t, find.byType(WaitingRoomScreen));

    final rival = WebSocketChannel.connect(Uri.parse(
        '${AppConfig.wsBase}/ws/v2/$code?name=Rakip&mode=tiki_taka_toe'));
    await rival.ready;

    await waitFor(t, find.byType(TikiTakaToeScreen),
        timeout: const Duration(seconds: 30), label: 'oyun tahtası');
    await hold(t, const Duration(seconds: 2));
    return rival;
  }

  /// Rakip adına hamle gönderir.
  void rivalMove(WebSocketChannel rival, int index,
      {String name = 'Rakip Oyuncu'}) {
    final symbol = GameSocket.instance.mySlot == 0 ? 'O' : 'X';
    rival.sink.add(jsonEncode({
      'type': 'relay',
      'data': {'index': index, 'symbol': symbol, 'playerName': name},
    }));
  }

  testWidgets('kendi hamlesi tahtaya işlenir ve sıra devreder', (t) async {
    final rival = await startGame(t);
    final socket = GameSocket.instance;

    expect(socket.playerTurn, isTrue, reason: 'kurucu ilk oynar');

    // Hamleyi aktarım kanalına yaz: sunucu geri yolladığında tahtaya işlenmeli.
    socket.relay(
        {'index': 5, 'symbol': socket.mySymbol, 'playerName': 'Harry Kane'});
    await hold(t, const Duration(seconds: 3));

    expect(find.text(socket.mySymbol), findsWidgets,
        reason: 'kendi hamlesi tahtada görünmeli');
    expect(find.text('Harry Kane'), findsOneWidget,
        reason: 'kutuda futbolcunun adı yazmalı');
    expect(socket.playerTurn, isFalse,
        reason: 'hamleden sonra sıra rakibe geçmeli');

    await rival.sink.close();
    await socket.disconnect();
  });

  testWidgets('rakip hamlesi işlenir, çalma hakkı ve uyarı çalışır', (t) async {
    final rival = await startGame(t);
    final socket = GameSocket.instance;
    final rivalSymbol = socket.mySlot == 0 ? 'O' : 'X';

    // Kendi hamlem
    socket.relay(
        {'index': 5, 'symbol': socket.mySymbol, 'playerName': 'Harry Kane'});
    await hold(t, const Duration(seconds: 2));

    // Rakip başka kutuya oynar
    rivalMove(rival, 6, name: 'Bukayo Saka');
    await hold(t, const Duration(seconds: 2));
    expect(find.text(rivalSymbol), findsWidgets,
        reason: 'rakip hamlesi tahtada olmalı');
    expect(socket.playerTurn, isTrue, reason: 'sıra bana dönmeli');

    // Rakip benim kutumu çalar
    rivalMove(rival, 5, name: 'Declan Rice');
    await hold(t, const Duration(milliseconds: 1200));

    expect(find.text('Rakibin kutunu çaldı!'), findsOneWidget,
        reason: 'çalma bildirimi görünmeli');
    expect(find.text('Declan Rice'), findsOneWidget,
        reason: 'çalınan kutuda yeni futbolcu yazmalı');

    await hold(t, const Duration(seconds: 2));

    // Rakibin kutusuna dokunmak: hakkım varken arama kutusu açılmalı
    await t.tap(find.byType(GestureDetector).at(6));
    await hold(t, const Duration(seconds: 2));

    await rival.sink.close();
    await socket.disconnect();
  });

  testWidgets('kutu seçimi bildirimi hamle sayılmaz', (t) async {
    // Kutu seçimi bildirimi de `index` taşır. Hamleyle karıştırılırsa
    // seçilen kutu doluyor, arama kutusu kapanıyor ve sıra devrediyordu.
    final rival = await startGame(t);
    final socket = GameSocket.instance;

    expect(socket.playerTurn, isTrue);

    socket.relay({'type': 'selectCell', 'index': 9});
    await hold(t, const Duration(seconds: 3));

    expect(socket.playerTurn, isTrue,
        reason: 'seçim bildirimi sırayı devretmemeli');
    expect(find.text(socket.mySymbol), findsNothing,
        reason: 'seçim bildirimi kutuyu doldurmamalı');

    // Rakibin seçim bildirimi de tahtayı doldurmamalı.
    rival.sink.add(jsonEncode({
      'type': 'relay',
      'data': {'type': 'selectCell', 'index': 10},
    }));
    await hold(t, const Duration(seconds: 2));

    final rivalSymbol = socket.mySlot == 0 ? 'O' : 'X';
    expect(find.text(rivalSymbol), findsNothing,
        reason: 'rakibin seçimi de kutuyu doldurmamalı');

    await rival.sink.close();
    await socket.disconnect();
  });

  testWidgets('süre dolumu sırayı devreder', (t) async {
    final rival = await startGame(t);
    final socket = GameSocket.instance;

    expect(socket.playerTurn, isTrue);
    socket.relay({'index': -1, 'symbol': socket.mySymbol});
    await hold(t, const Duration(seconds: 3));

    expect(socket.playerTurn, isFalse,
        reason: 'süre dolunca sıra rakibe geçmeli');

    await rival.sink.close();
    await socket.disconnect();
  });
}
