import 'package:flutter/material.dart';

import 'package:footttball/app/app.dart';
import 'package:footttball/core/session.dart';
import 'package:footttball/core/sound.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Kimlik ve ses tercihi açılışta yüklenir; ikisi de hızlı ve hatasız.
  await Future.wait([
    Session.instance.ensurePlayerId(),
    Sound.instance.init(),
  ]);
  runApp(const TikiTakaToeApp());
}
