import 'dart:async';
import 'package:flutter/material.dart';
import 'package:footttball/Models/teamModel.dart';
import 'package:footttball/Rooms/startPage.dart';
import 'package:footttball/home.dart';
import 'package:footttball/home.dart';
import 'package:footttball/Services/websocket.dart'; // Import WebSocketManager
import 'dart:convert'; // For jsonEncode
import 'package:footttball/Helper/globals.dart' as globals;

class VsScreen extends StatefulWidget {
  final TeamModel teammodel;
  final String gamemode;
  final String player1Name;
  final String player2Name;
  final int roundCount;

  const VsScreen({
    Key? key,
    required this.teammodel,
    required this.gamemode,
    required this.player1Name,
    required this.player2Name,
    required this.roundCount,
  }) : super(key: key);

  @override
  State<VsScreen> createState() => _VsScreenState();
}

class _VsScreenState extends State<VsScreen> with TickerProviderStateMixin {
  late AnimationController _p1Controller;
  late Animation<Offset> _p1Animation;

  late AnimationController _p2Controller;
  late Animation<Offset> _p2Animation;

  late AnimationController _vsController;
  late Animation<double> _vsScaleAnimation;

  // Mutable names
  late String _p1Name;
  late String _p2Name;

  @override
  void initState() {
    super.initState();

    // Initialize names from Widget or WebSocket Cache
    _p1Name = widget.player1Name;
    _p2Name = widget.player2Name;

    // Check if WebSocket has cached data and strictly assign
    // Assuming X is P1 (Left) and O is P2 (Right)
    if (WebSocketManager().p1Name != "Player 1") {
       _p1Name = WebSocketManager().p1Name;
    }
    if (WebSocketManager().p2Name != "Player 2") {
       _p2Name = WebSocketManager().p2Name;
    }

    // Listen for name updates
    WebSocketManager().onNameAnnounced = (name, type) {
      print("VS Screen Received Name: $name ($type)"); // Debug log
      if (mounted) {
        setState(() {
           if (type == "X") {
             _p1Name = name;
           } else if (type == "O") {
             _p2Name = name;
           } else {
             // Fallback: if we don't know type, fill the first placeholder
             if (_p2Name == "Player 2" || _p2Name == "Opponent") {
               _p2Name = name;
             }
           }
        });
      }
    };

    // Player 1 Slide In (Left to Center)
    _p1Controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _p1Animation = Tween<Offset>(
      begin: const Offset(-1.5, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _p1Controller, curve: Curves.easeOutBack));

    // Player 2 Slide In (Right to Center)
    _p2Controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _p2Animation = Tween<Offset>(
      begin: const Offset(1.5, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _p2Controller, curve: Curves.easeOutBack));

    // VS Logo Scale/Bounce
    _vsController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _vsScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _vsController, curve: Curves.elasticOut));

    // Sequence the animations
    _startAnimations();
    
    // ANNNOUNCE NAME EARLY to ensure VsScreen updates
    // Use a slight delay to ensure socket is ready/connected
    Future.delayed(Duration(milliseconds: 300), () {
      if (WebSocketManager().initialType.isNotEmpty) {
         WebSocketManager().send(jsonEncode({
          "type": "announceName",
          "name": globals.player1Name, // My local name
          "playerType": WebSocketManager().initialType
        }));
      }
    });
  }

  void _startAnimations() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _p1Controller.forward();
    _p2Controller.forward();
    await Future.delayed(const Duration(milliseconds: 600));
    _vsController.forward();

    // Navigate to Game after 3 seconds total
    Timer(const Duration(seconds: 4), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => TikiTakaToeGame(
            teammodel: widget.teammodel,
            gamemode: widget.gamemode,
            player1Name: widget.player1Name, // Pass original for now, logic inside game handles it
            player2Name: _p2Name, // Pass updated name
            roundCount: widget.roundCount,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _p1Controller.dispose();
    _p2Controller.dispose();
    _vsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Background
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('images/arka2.PNG'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          
          // Content
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Push content down to avoid Logo overlap
              SizedBox(height: 120), 

              // Player 1 (Upper Leftish)
              SlideTransition(
                position: _p1Animation,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  margin: EdgeInsets.only(bottom: 20, right: 50),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(50),
                      bottomRight: Radius.circular(50),
                    ),
                    border: Border.all(
                      color: Colors.cyanAccent.withOpacity(0.5),
                      width: 2,
                    ),
                    gradient: LinearGradient(
                      colors: [Colors.black54, Colors.cyanAccent.withOpacity(0.2)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person, color: Colors.cyanAccent, size: 30),
                      SizedBox(width: 15),
                      Text(
                        _p1Name.toUpperCase(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // VS Logo Center
              ScaleTransition(
                scale: _vsScaleAnimation,
                child: Container(
                  height: 120,
                  width: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                     gradient: LinearGradient(
                        colors: [
                          Color(0xFFFF0055), // Red/Pink
                          Color(0xFF8000FF), // Purple
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFFFF0055).withOpacity(0.6),
                        blurRadius: 50,
                        spreadRadius: 5,
                      )
                    ]
                  ),
                  child: Center(
                    child: Text(
                      "VS",
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w900,
                        fontSize: 50,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black45,
                            offset: Offset(3, 3),
                            blurRadius: 5,
                          )
                        ]
                      ),
                    ),
                  ),
                ),
              ),

              // Player 2 (Lower Rightish)
              SlideTransition(
                position: _p2Animation,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  margin: EdgeInsets.only(top: 20, left: 50),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(50),
                      bottomLeft: Radius.circular(50),
                    ),
                    border: Border.all(
                      color: Colors.purpleAccent.withOpacity(0.5),
                      width: 2,
                    ),
                     gradient: LinearGradient(
                      colors: [Colors.purpleAccent.withOpacity(0.2), Colors.black54],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _p2Name.toUpperCase(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                        ),
                      ),
                      SizedBox(width: 15),
                      Icon(Icons.person_outline, color: Colors.purpleAccent, size: 30),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
