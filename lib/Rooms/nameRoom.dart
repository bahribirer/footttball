import 'dart:async';
import 'package:flutter/material.dart';
import 'package:footttball/Helper/loading.dart'; // loading.dart dosyasını dahil edin
import 'package:footttball/Rooms/startPage.dart';
import 'package:footttball/Helper/globals.dart' as globals;

class NameRoom extends StatefulWidget {
  const NameRoom({Key? key}) : super(key: key);

  @override
  _NameRoomState createState() => _NameRoomState();
}

class _NameRoomState extends State<NameRoom> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  TextEditingController _nameController = TextEditingController();
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null,
      body: Stack(
        children: [
          // Background image
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('images/arka2.PNG'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Premium Name Input Field with Breathing Animation
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.30, // Moved down from 0.40 to 0.30
            left: 20,
            right: 20,
            child: Center(
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  return Container(
                    width: MediaQuery.of(context).size.width * 0.75, // Narrower width
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: LinearGradient(
                        colors: [Colors.cyanAccent, Colors.purpleAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.cyanAccent.withOpacity(0.4 + (0.3 * _animation.value)),
                          blurRadius: 20 + (10 * _animation.value),
                          spreadRadius: 2 + (3 * _animation.value),
                          offset: Offset(0, 0),
                        ),
                        BoxShadow(
                          color: Colors.purpleAccent.withOpacity(0.3 + (0.2 * _animation.value)),
                          blurRadius: 15 + (15 * _animation.value),
                          spreadRadius: 1,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    padding: EdgeInsets.all(3), // Border width
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                      decoration: BoxDecoration(
                        color: Color(0xFF1A1A2E), // Dark game background
                        borderRadius: BorderRadius.circular(27),
                      ),
                      child: TextField(
                        controller: _nameController,
                        enableInteractiveSelection: false, // Fix for crash
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 2.0,
                        ),
                        cursorColor: Colors.cyanAccent,
                        decoration: InputDecoration(
                          hintText: 'ENTER YOUR NAME',
                          hintStyle: TextStyle(
                            color: Colors.white38,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                          border: InputBorder.none,
                          prefixIcon: Icon(
                            Icons.person,
                            color: Colors.cyanAccent,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // Premium Play Button
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.15,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isLoading ? null : _navigateToStartPage,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.7, // Bigger button
                  padding: EdgeInsets.symmetric(vertical: 20), // Taller
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF6A11CB),
                        Color(0xFF2575FC),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF6A11CB).withOpacity(0.5),
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'START',
                      style: TextStyle(
                        fontSize: 28, // Larger font
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 3.0,
                        shadows: [
                          Shadow(
                            color: Colors.black45,
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ),

          // Creative Loading Overlay
          if (_isLoading)
            Positioned.fill(
              child: _GameLoadingIndicator(),
            ),
        ],
      ),
    );
  }

  void _navigateToStartPage() {
    if (_nameController.text.isEmpty) {
      _showNameNotEnteredDialog(context);
    } else {
      setState(() {
        _isLoading = true;
      });

      // Assign the entered name to the global variable
      globals.player1Name = _nameController.text; // Player 1's name

      Timer(Duration(seconds: 3), () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => StartPage(),
          ),
        );
        setState(() {
          _isLoading = false;
        });
      });
    }
  }

  void _showNameNotEnteredDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.transparent,
          child: _AnimatedExclamationDialog(), // Use the same animated dialog
        );
      },
    );
  }

}

// You can reuse the _AnimatedExclamationDialog class as is from the CreateRoomPage
class _AnimatedExclamationDialog extends StatefulWidget {
  @override
  __AnimatedExclamationDialogState createState() =>
      __AnimatedExclamationDialogState();
}

class __AnimatedExclamationDialogState extends State<_AnimatedExclamationDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(3), // Border width
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [Colors.cyanAccent, Colors.purpleAccent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.purpleAccent.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Container(
        padding: EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: Color(0xFF1A1A2E), // Dark background
          borderRadius: BorderRadius.circular(17),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ScaleTransition(
              scale: _animation,
              child: Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.redAccent.withOpacity(0.1),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 50,
                  color: Colors.redAccent,
                ),
              ),
            ),
            SizedBox(height: 20),
            Text(
              "Please Enter Name",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: 10),
            Text(
              "You need to enter a name to proceed.",
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 30),
            GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
              },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 40),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.redAccent, Colors.pinkAccent],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.redAccent.withOpacity(0.4),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  "OK",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameLoadingIndicator extends StatefulWidget {
  @override
  __GameLoadingIndicatorState createState() => __GameLoadingIndicatorState();
}

class __GameLoadingIndicatorState extends State<_GameLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                // Rotating Neon Ring
                RotationTransition(
                  turns: _controller,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          Colors.transparent,
                          Colors.cyanAccent,
                          Colors.purpleAccent,
                          Colors.transparent,
                        ],
                        stops: [0.0, 0.4, 0.6, 1.0],
                      ),
                    ),
                  ),
                ),
                // Inner Glow
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyanAccent.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                ),
                // Football Icon
                Icon(
                  Icons.sports_soccer,
                  size: 50,
                  color: Colors.white,
                ),
              ],
            ),
            SizedBox(height: 30),
            Text(
              "ENTERING PITCH...",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 3.0,
                shadows: [
                  Shadow(
                    color: Colors.cyanAccent,
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
