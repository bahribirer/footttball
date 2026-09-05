import 'package:flutter/material.dart';
import 'package:footttball/features/onboarding/onboarding_screen.dart';
import 'package:lottie/lottie.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
      Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => OnboardingScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('images/arka2.PNG'), // Dark/Space theme
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Lottie Animation
          Center(
            child: GestureDetector(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => OnboardingScreen(),
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
        ],
      ),
    );
  }
}
