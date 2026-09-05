// Uçtan uca arayüz testleri.
//
// Yerel backend ayakta olmalı. Çalıştırmak için:
//   flutter test integration_test/game_flow_test.dart -d <cihaz> \
//     --dart-define=API_BASE=http://127.0.0.1:8000 \
//     --dart-define=WS_BASE=ws://127.0.0.1:8000
//
// Rakip oyuncu testin içinden WebSocket ile bağlanarak taklit edilir; böylece
// tek cihazda iki kişilik akışın tamamı doğrulanabilir.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:footttball/app/app.dart';
import 'package:footttball/core/config/app_config.dart';
import 'package:footttball/core/session.dart';
import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/services/game_socket.dart';
import 'package:footttball/features/games/category_race/category_race_screen.dart';
import 'package:footttball/features/games/last_letter/last_letter_screen.dart';
import 'package:footttball/features/games/player_guess/player_guess_screen.dart';
import 'package:footttball/features/games/tiki_taka_toe/tiki_taka_toe_screen.dart';
import 'package:footttball/features/lobby/create_room_screen.dart';
import 'package:footttball/features/lobby/start_page.dart';
import 'package:footttball/features/lobby/waiting_room_screen.dart';
import 'package:footttball/features/modes/mode_select_screen.dart';
import 'package:footttball/features/onboarding/onboarding_screen.dart';
import 'package:footttball/features/profile/name_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Ekranlarda sürekli çalışan zamanlayıcılar olduğu için `pumpAndSettle`
  /// kullanılamaz; hedef widget görünene kadar kısa aralıklarla pump edilir.
  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 25),
    String? label,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 120));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('Beklenen görünmedi: ${label ?? finder.toString()}');
  }

  Future<void> pumpFor(WidgetTester tester, Duration duration) async {
    final deadline = DateTime.now().add(duration);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Testler mod menüsünden başlar; açılış akışı ayrı bir testte doğrulanır.
  Future<void> openMenu(WidgetTester tester) async {
    Session.instance.playerName = 'Bahri';
    await tester.pumpWidget(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ModeSelectScreen(),
    ));
    await pumpUntil(tester, find.text('OYUN MODU SEÇ'), label: 'mod menüsü');
  }

  /// Menüden oda kurar ve sunucunun verdiği oda kodunu döndürür.
  Future<String> createRoom(WidgetTester tester, GameMode mode) async {
    await tester.tap(find.byKey(ValueKey('mode_card_${mode.id}')));
    await pumpFor(tester, const Duration(milliseconds: 500));

    await tester.tap(find.byKey(ValueKey('play_${mode.id}')));
    await pumpUntil(tester, find.byType(StartPage), label: 'oda kur/katıl ekranı');

    await tester.tap(find.byKey(const ValueKey('btn_create_room')));
    await pumpUntil(tester, find.byType(CreateRoomScreen), label: 'oda kurma ekranı');
    await pumpUntil(tester, find.text('ODA KODU'), label: 'oda kodu');

    // Kod, her hanesi ayrı kutuda gösterildiği için birleştirilir.
    final digits = find
        .descendant(of: find.byType(CreateRoomScreen), matching: find.byType(Text))
        .evaluate()
        .map((element) => (element.widget as Text).data ?? '')
        .where((text) => text.length == 1 && int.tryParse(text) != null)
        .join();

    expect(digits.length, 4, reason: 'Sunucudan 4 haneli oda kodu bekleniyor');
    return digits;
  }

  /// Rakip oyuncuyu taklit eden WebSocket bağlantısı.
  Future<WebSocketChannel> joinAsRival(String code, GameMode mode) async {
    final channel = WebSocketChannel.connect(Uri.parse(
      '${AppConfig.wsBase}/ws/v2/$code?name=Rakip&mode=${mode.id}',
    ));
    await channel.ready;
    return channel;
  }

  tearDown(() async {
    await GameSocket.instance.disconnect();
    GameSocket.instance.clearCallbacks();
    Session.instance
      ..playerName = ''
      ..selectedMode = GameMode.tikiTakaToe
      ..roundCount = 1;
  });

  testWidgets('Açılış akışı: onboarding, isim girişi ve mod menüsü', (tester) async {
    await tester.pumpWidget(const TikiTakaToeApp());

    await pumpUntil(tester, find.byType(OnboardingScreen),
        timeout: const Duration(seconds: 15), label: 'onboarding');

    await tester.tap(find.text('Skip'));
    await pumpUntil(tester, find.byType(NameRoom), label: 'isim ekranı');

    await tester.enterText(find.byType(TextField).first, 'Bahri');
    await pumpFor(tester, const Duration(milliseconds: 300));

    await tester.tap(find.text('BAŞLA'));
    await pumpUntil(tester, find.byType(ModeSelectScreen), label: 'mod menüsü');

    expect(find.text('BAHRI'), findsOneWidget);
    for (final mode in GameMode.values) {
      expect(find.text(mode.title), findsOneWidget,
          reason: '${mode.title} menüde görünmeli');
    }
  });

  testWidgets('Son Harf: rakip katılınca oyun başlar, cevap sunucuya gider',
      (tester) async {
    await openMenu(tester);
    final code = await createRoom(tester, GameMode.lastLetter);

    await tester.tap(find.byKey(const ValueKey('btn_play')));
    await pumpUntil(tester, find.byType(WaitingRoomScreen), label: 'bekleme odası');
    expect(
      find.descendant(
        of: find.byType(WaitingRoomScreen),
        matching: find.text('ODA KODU'),
      ),
      findsOneWidget,
    );

    final rival = await joinAsRival(code, GameMode.lastLetter);
    final rivalMessages = <Map<String, dynamic>>[];
    rival.stream.listen((raw) =>
        rivalMessages.add(jsonDecode(raw as String) as Map<String, dynamic>));

    await pumpUntil(tester, find.byType(LastLetterScreen),
        timeout: const Duration(seconds: 25), label: 'Son Harf ekranı');

    // Saat kartları ve harf paneli görünmeli.
    expect(find.text('50'), findsWidgets, reason: '50 saniyelik saatler');
    expect(
      find.text('BU HARFLE BAŞLA').evaluate().isNotEmpty ||
          find.text('SERBEST BAŞLANGIÇ').evaluate().isNotEmpty,
      isTrue,
      reason: 'Harf paneli görünmeli',
    );

    // Sıra bizde değilse rakip ilk hamleyi yapsın.
    final socket = GameSocket.instance;
    if (socket.mySlot != (socket.lastState['current_turn'] as int? ?? 0)) {
      rival.sink.add(jsonEncode(
          {'type': 'action', 'action': 'answer', 'value': 'Erling Haaland'}));
      await pumpFor(tester, const Duration(seconds: 3));
    }

    await tester.enterText(find.byType(TextField).first, 'David Silva');
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.send_rounded));
    await pumpFor(tester, const Duration(seconds: 3));

    expect(rivalMessages.any((m) => m['type'] == 'start'), isTrue,
        reason: 'Rakip start mesajını almalı');
    expect(
      rivalMessages.any((m) => m['event'] == 'accepted' || m['event'] == 'rejected'),
      isTrue,
      reason: 'Gönderilen cevap sunucuda değerlendirilmeli',
    );

    await rival.sink.close();
  });

  testWidgets('Kategori Yarışı: kategori sunucudan gelir', (tester) async {
    await openMenu(tester);
    final code = await createRoom(tester, GameMode.categoryRace);

    await tester.tap(find.byKey(const ValueKey('btn_play')));
    await pumpUntil(tester, find.byType(WaitingRoomScreen), label: 'bekleme odası');

    final rival = await joinAsRival(code, GameMode.categoryRace);
    await pumpUntil(tester, find.byType(CategoryRaceScreen),
        timeout: const Duration(seconds: 25), label: 'Kategori Yarışı ekranı');

    expect(find.text('KATEGORİ'), findsOneWidget);
    expect(find.text('Kategori yükleniyor...'), findsNothing,
        reason: 'Kategori etiketi dolu gelmeli');

    await rival.sink.close();
  });

  testWidgets('Oyuncu Tahmin: geri sayım ve seçim aşaması', (tester) async {
    await openMenu(tester);
    final code = await createRoom(tester, GameMode.playerGuess);

    await tester.tap(find.byKey(const ValueKey('btn_play')));
    await pumpUntil(tester, find.byType(WaitingRoomScreen), label: 'bekleme odası');

    final rival = await joinAsRival(code, GameMode.playerGuess);
    await pumpUntil(tester, find.byType(PlayerGuessScreen),
        timeout: const Duration(seconds: 25), label: 'Oyuncu Tahmin ekranı');

    await pumpUntil(tester, find.text('HAZIR OL'),
        timeout: const Duration(seconds: 12), label: 'hazırlık geri sayımı');

    await pumpUntil(
      tester,
      find.byWidgetPredicate((widget) =>
          widget is Text &&
          (widget.data == 'MİLLİ TAKIMINI SEÇ' ||
              widget.data == 'KULÜBÜNÜ SEÇ' ||
              widget.data == 'RAKİBİN SEÇİYOR')),
      timeout: const Duration(seconds: 18),
      label: 'seçim aşaması',
    );

    await rival.sink.close();
  });

  testWidgets('Tiki Taka Toe: lig seçilir ve tahta çizilir', (tester) async {
    await openMenu(tester);
    final code = await createRoom(tester, GameMode.tikiTakaToe);

    await tester.tap(find.byKey(const ValueKey('league_Premier League')));
    await pumpFor(tester, const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const ValueKey('btn_play')));
    await pumpUntil(tester, find.text('SERİ UZUNLUĞU'), label: 'seri seçimi');

    await tester.tap(find.byKey(const ValueKey('rounds_3')));
    await pumpUntil(tester, find.byType(WaitingRoomScreen), label: 'bekleme odası');

    final rival = await joinAsRival(code, GameMode.tikiTakaToe);
    await pumpUntil(tester, find.byType(TikiTakaToeScreen),
        timeout: const Duration(seconds: 30), label: 'oyun tahtası');

    expect(find.byType(GridView), findsOneWidget, reason: '4x4 tahta çizilmeli');

    // Kurucunun lig ve tur seçimi sunucudaki odaya işlenmiş olmalı.
    // (Oda kodu seçimden önce rezerve edildiği için bu bir kez atlanmıştı.)
    final payload = GameSocket.instance.startPayload;
    expect(payload['league_id'], 'GB1',
        reason: 'Seçilen lig sunucuya iletilmeli');
    expect(payload['round_count'], 3,
        reason: 'Seçilen seri uzunluğu sunucuya iletilmeli');

    await rival.sink.close();
  });
}
