import 'dart:math';
import 'package:flutter/material.dart';
import 'start.dart';
import 'package:lottie/lottie.dart';

void main() {
  runApp(const TikiTakaToeApp());
}

class TikiTakaToeApp extends StatelessWidget {
  const TikiTakaToeApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tiki Taka Toe',
      home: SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(seconds: 6), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => StartPage(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: GestureDetector(
          onTap: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => StartPage(),
              ),
            );
          },
          child: Lottie.network(
            'https://lottie.host/adf8f905-7303-48b1-a372-94e27b62080e/7kL5Cen7Px.json',
            errorBuilder: (context, error, stackTrace) {
              print('Lottie Error: $error');
              return Text('Error loading animation');
            },
          ),
        ),
      ),
    );
  }
}
