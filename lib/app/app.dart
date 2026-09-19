import 'package:flutter/material.dart';

import 'package:footttball/core/notices.dart';
import 'package:footttball/core/theme/app_theme.dart';
import 'package:footttball/features/splash/splash_screen.dart';

class TikiTakaToeApp extends StatelessWidget {
  const TikiTakaToeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: Notices.instance.navigatorKey,
      title: 'Tiki Taka Toe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.material(),
      home: const SplashScreen(),
    );
  }
}
