import 'dart:math';
import 'package:flutter/material.dart';
import 'package:footttball/Models/teamModel.dart';
import 'package:footttball/Rooms/waitingRoom.dart';
import 'package:footttball/Rooms/startPage.dart'; // Import StartPage to navigate back
import 'package:footttball/getInfo.dart';
import 'package:footttball/home.dart';
import 'package:footttball/Models/players.dart';
import '../Services/api_service.dart';
import '../splash.dart';
import '../main.dart';

class JoinRoomPage extends StatefulWidget {
  @override
  _JoinRoomPageState createState() => _JoinRoomPageState();
}

class _JoinRoomPageState extends State<JoinRoomPage> with SingleTickerProviderStateMixin {
  String? roomCode;
  String selectedGameMode = ''; // Seçilen oyun modu
  late FocusNode _roomCodeFocusNode;
  TextEditingController roomcode = TextEditingController();
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _roomCodeFocusNode = FocusNode();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _roomCodeFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null,
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.asset(
              'images/arka1.png', // Using the provided background image
              fit: BoxFit.cover,
            ),
          ),
          // Custom Back Button Positioned
          Positioned(
            top: 50,
            left: 20,
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => StartPage()),
                );
              },
              child: Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.2),
                      Colors.white.withOpacity(0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.5),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).size.height * 0.45,
            left: 0,
            right: 0,
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Premium Input Field with Breathing Animation
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.75, // Narrower width
                  child: AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                    return Container(
                      padding: EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          colors: [
                            Colors.orangeAccent,
                            Colors.pinkAccent,
                          ], // Animate colors if desired, sticking to glow for now
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.pinkAccent.withOpacity(0.4 + (0.3 * _animation.value)),
                            blurRadius: 15 + (10 * _animation.value),
                            spreadRadius: 1 + (3 * _animation.value),
                            offset: Offset(0, 5),
                          ),
                          BoxShadow(
                            color: Colors.orangeAccent.withOpacity(0.3 + (0.2 * _animation.value)),
                            blurRadius: 25 + (15 * _animation.value),
                            spreadRadius: 2,
                            offset: Offset(0, 0),
                          ),
                        ],
                      ),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                        decoration: BoxDecoration(
                          color: Color(0xFF1A1A2E),
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: TextField(
                          controller: roomcode,
                          enableInteractiveSelection: false, // Fix for crash
                          decoration: InputDecoration(
                            hintText: "Enter Room Code",
                            hintStyle: TextStyle(
                              color: Colors.white38,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                            prefixIcon: Icon(
                              Icons.vpn_key_rounded,
                              color: Colors.orangeAccent,
                            ),
                            border: InputBorder.none,
                          ),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 2.5,
                          ),
                          cursorColor: Colors.orangeAccent,
                          textAlign: TextAlign.center,
                          focusNode: _roomCodeFocusNode,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    );
                  },
                ),
              ),
                SizedBox(height: 60), // Moved button further down
                // Premium JOIN Button
                GestureDetector(
                  onTap: () async {
                    if (roomcode.text.isEmpty) {
                      _showCodeNotEnteredDialog(context);
                    } else {
                      // Check if room exists before joining
                      _showLoadingDialog(context);
                      try {
                        final trimmedCode = roomcode.text.trim();
                        final result = await ApiService.checkRoom(trimmedCode);
                        Navigator.of(context).pop(); // dismiss loading
                        
                        if (result['room_exists'] == true && result['is_joinable'] == true) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => WaitingRoom(
                                room_id: roomcode.text,
                                teammodel: TeamModel(nations: [""], clubs: [""]),
                                gamemode: "",
                              ),
                            ),
                          );
                        } else if (result['room_exists'] == true && result['is_joinable'] == false) {
                          _showRoomErrorDialog(context, "Room Full", "This room already has 2 players.");
                        } else {
                          _showRoomErrorDialog(context, "Room Not Found", "No room with code \"${roomcode.text}\" exists.\nAsk the host for the correct code.");
                        }
                      } catch (e) {
                        Navigator.of(context).pop(); // dismiss loading
                        _showRoomErrorDialog(context, "Connection Error", "Could not reach the server.\nCheck your connection.");
                      }
                    }
                  },
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.7, // Bigger button
                    padding: EdgeInsets.symmetric(vertical: 20), // Taller button
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
                          color: Color(0xFF2575FC).withOpacity(0.5),
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
                        "JOIN GAME",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24, // Larger font
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
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
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => Center(
        child: Container(
          padding: EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: Colors.amberAccent,
                strokeWidth: 3,
              ),
              SizedBox(height: 16),
              Material(
                color: Colors.transparent,
                child: Text(
                  "Checking room...",
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRoomErrorDialog(BuildContext context, String title, String body) {
    showGeneralDialog(
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: Duration(milliseconds: 350),
      pageBuilder: (ctx, anim1, anim2) => Center(
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: 30),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.redAccent.withOpacity(0.4),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.redAccent.withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 24),
                Text("🚫", style: TextStyle(fontSize: 48)),
                SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    shadows: [
                      Shadow(
                        blurRadius: 10,
                        color: Colors.redAccent.withOpacity(0.5),
                        offset: Offset(0, 0),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 14),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    body,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
                SizedBox(height: 24),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.amberAccent, Colors.orangeAccent],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withOpacity(0.4),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          "TRY AGAIN",
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
      transitionBuilder: (ctx, anim1, anim2, child) => ScaleTransition(
        scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
        child: FadeTransition(
          opacity: anim1,
          child: child,
        ),
      ),
      context: context,
    );
  }

  void _showCodeNotEnteredDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.transparent,
          child: _AnimatedExclamationDialog(),
        );
      },
    );
  }
}

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
      padding: EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [Colors.orangeAccent, Colors.deepOrange],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.deepOrange.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Container(
        padding: EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: Color(0xFF1A1A2E),
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
              "Please Enter Code",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: 10),
            Text(
              "You need to enter a room code to proceed.",
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
