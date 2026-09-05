// Ekranların farklı telefon boyutlarında taşma vermeden çizildiğini doğrular.
//
// Flutter, bir satır/sütun sığmadığında "RenderFlex overflowed" hatası
// bildirir ve test bunu yakalar. Böylece küçük ekranlı cihazlarda ortaya
// çıkan çerçeve hataları, cihazda denemeye gerek kalmadan yakalanır.
//
// Çalıştırmak için:  flutter test test/responsive_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footttball/core/session.dart';
import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/models/team_model.dart';
import 'package:footttball/features/games/tiki_taka_toe/tiki_taka_toe_screen.dart';
import 'package:footttball/features/lobby/create_room_screen.dart';
import 'package:footttball/features/lobby/join_room_screen.dart';
import 'package:footttball/features/lobby/start_page.dart';
import 'package:footttball/features/lobby/vs_screen.dart';
import 'package:footttball/features/modes/mode_select_screen.dart';
import 'package:footttball/features/onboarding/onboarding_screen.dart';
import 'package:footttball/features/profile/name_screen.dart';

/// Piyasadaki en dar ve en geniş yaygın cihazlar.
const _sizes = <String, Size>{
  'küçük Android (320x568)': Size(320, 568),
  'Galaxy S (360x640)': Size(360, 640),
  'iPhone SE (375x667)': Size(375, 667),
  'iPhone 16 (393x852)': Size(393, 852),
  'Pro Max (430x932)': Size(430, 932),
  'tablet (768x1024)': Size(768, 1024),
};

void main() {
  setUp(() {
    Session.instance
      ..playerName = 'Bahri'
      ..selectedMode = GameMode.tikiTakaToe;
  });

  /// Ekranı verilen boyutta çizer; taşma olursa test hata verir.
  Future<void> render(WidgetTester tester, Size size, Widget screen) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark),
      home: screen,
    ));

    // Ağ çağrıları ve animasyonlar sürerken birkaç kare ilerletilir;
    // `pumpAndSettle` sonsuz döngüdeki animasyonlarda takılır.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Her ekran, her boyutta ayrı bir test olarak çalışır.
  void screenTest(String name, Widget Function() build, {GameMode? mode}) {
    for (final entry in _sizes.entries) {
      testWidgets('$name — ${entry.key}', (tester) async {
        if (mode != null) Session.instance.selectedMode = mode;
        await render(tester, entry.value, build());
      });
    }
  }

  group('açılış akışı', () {
    screenTest('Onboarding', () => const OnboardingScreen());
    screenTest('İsim girişi', () => const NameRoom());
    screenTest('Mod seçimi', () => const ModeSelectScreen());
  });

  group('lobi', () {
    screenTest('Oda kur/katıl', () => const StartPage());
    screenTest('Odaya katıl', () => const JoinRoomScreen());
    screenTest('VS ekranı', () => const VsScreen(mode: GameMode.tikiTakaToe));
  });

  // Oda kurma ekranı moda göre farklı ayar bölümleri gösterir; en uzun
  // içerik Kategori Yarışı'nda (5 kategori + süre) ve Tiki Taka Toe'da
  // (6 lig + seri uzunluğu) oluşuyor.
  group('oda kurma', () {
    for (final mode in GameMode.values) {
      screenTest('Oda kur — ${mode.title}', () => const CreateRoomScreen(),
          mode: mode);
    }
  });

  group('oyun tahtası', () {
    screenTest(
      'Tiki Taka Toe',
      () => TikiTakaToeScreen(
        teammodel: TeamModel(
          nations: const ['Turkey', 'Portugal', 'Brazil'],
          clubs: const ['Galatasaray', 'Fenerbahce', 'Besiktas JK'],
        ),
        leagueId: 'TR1',
        roundCount: 3,
      ),
    );
  });

  group('mod seçiminde uzun isim', () {
    // Uzun oyuncu adı rozetin taşmasına yol açmamalı.
    testWidgets('çok uzun oyuncu adı taşma yapmaz', (tester) async {
      Session.instance.playerName = 'Abdurrahman Muhammed Çelebioğlu Karahanlı';
      await render(tester, const Size(320, 568), const ModeSelectScreen());
    });
  });
}
