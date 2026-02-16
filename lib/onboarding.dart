import 'package:flutter/material.dart';
import 'package:footttball/Rooms/nameRoom.dart';

class OnboardingScreen extends StatefulWidget {
  @override
  _OnboardingScreenState createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  List<Map<String, String>> onboardingData = [
    {
      "title": "WELCOME TO\nTIKI TAKA TOE",
      "text": "The classic game meets football strategy! Master the pitch and outsmart your opponent.",
      "image": "images/onboarding_football.png",
    },
    {
      "title": "MASTER THE BOARD",
      "text": "Place your team's players strategically to form a line of three. Offense and defense are key!",
      "image": "images/onboarding_board.png",
    },
    {
      "title": "CONQUER LEAGUES",
      "text": "Choose your favorite league, challenge friends, and become the ultimate champion!",
      "image": "images/onboarding_trophy.png",
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('images/arka2.PNG'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Content
          Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (value) {
                    setState(() {
                      _currentPage = value;
                    });
                  },
                  itemCount: onboardingData.length,
                  itemBuilder: (context, index) => OnboardingContent(
                    title: onboardingData[index]["title"]!,
                    text: onboardingData[index]["text"]!,
                    image: onboardingData[index]["image"]!,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Dot Indicator
                    Row(
                      children: List.generate(
                        onboardingData.length,
                        (index) => buildDot(index: index),
                      ),
                    ),
                    // Next/Start Button
                    GestureDetector(
                      onTap: () {
                        if (_currentPage == onboardingData.length - 1) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (context) => NameRoom()),
                          );
                        } else {
                          _pageController.nextPage(
                            duration: Duration(milliseconds: 300),
                            curve: Curves.ease,
                          );
                        }
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.cyanAccent, Colors.purpleAccent],
                          ),
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.purpleAccent.withOpacity(0.4),
                              blurRadius: 10,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Text(
                          _currentPage == onboardingData.length - 1 ? "START" : "NEXT",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Skip Button
          Positioned(
            top: 50,
            right: 20,
            child: TextButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => NameRoom()),
                );
              },
              child: Text(
                "Skip",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  AnimatedContainer buildDot({required int index}) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 200),
      margin: EdgeInsets.only(right: 5),
      height: 6,
      width: _currentPage == index ? 20 : 6,
      decoration: BoxDecoration(
        color: _currentPage == index ? Colors.cyanAccent : Colors.grey,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class OnboardingContent extends StatelessWidget {
  final String title, text, image;

  const OnboardingContent({
    Key? key,
    required this.title,
    required this.text,
    required this.image,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Spacer(flex: 3), // Push content down to avoid "TIKI TAKA TOE" header
          // Image with Animation (Smaller)
          SizedBox(
            height: 150, // Smaller image
            width: 150,
            child: Image.asset(
              image,
              fit: BoxFit.contain,
            ),
          ),
          SizedBox(height: 40),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24, // Slightly smaller title
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.5,
              shadows: [
                Shadow(
                  color: Colors.purpleAccent.withOpacity(0.5),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
          SizedBox(height: 15),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14, // Smaller text
              color: Colors.white70,
              height: 1.4,
            ),
          ),
          Spacer(flex: 1), // Bottom spacing
        ],
      ),
    );
  }
}
