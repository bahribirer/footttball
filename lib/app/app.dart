import 'package:flutter/material.dart';

import 'package:footttball/features/splash/splash_screen.dart';

class TikiTakaToeApp extends StatelessWidget {
  const TikiTakaToeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tiki Taka Toe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F1E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6A11CB),
          secondary: Colors.cyanAccent,
          surface: Color(0xFF14142A),
        ),
        fontFamily: 'Roboto',
        useMaterial3: false,
      ),
      home: const SplashScreen(),
    );
  }
}
