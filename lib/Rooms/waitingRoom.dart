import 'dart:convert';
import 'dart:math' as Math;

import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
import 'package:footttball/Services/api_service.dart';
import 'package:footttball/Helper/helper.dart';
import 'package:footttball/Models/teamModel.dart';
import 'package:footttball/Services/websocket.dart';
import 'package:footttball/getInfo.dart';
import 'package:footttball/home.dart';
import 'package:footttball/main.dart';
import 'package:footttball/Models/players.dart';
import 'package:footttball/Rooms/startPage.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:footttball/Helper/globals.dart' as globals;

class WaitingRoom extends StatefulWidget {
  String room_id;
  TeamModel? teammodel; // Nullable for Host
  String gamemode;
  final int? roundCount; // Add roundCount as optional parameter

  WaitingRoom(
      {super.key,
      required this.room_id,
      this.teammodel,
      required this.gamemode,
      this.roundCount});

  @override
  State<WaitingRoom> createState() => _WaitingRoomState();
}

class _WaitingRoomState extends State<WaitingRoom>
    with SingleTickerProviderStateMixin {
  String firstMessage = "";
  bool control = true;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isLoadingData = false;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    var room_id = widget.room_id;
    
    // 1. Prioritize connection to "create" the room on backend
    WebSocketManager().connect('wss://tikitakatoe.com/ws/$room_id', context,
        widget.teammodel, widget.gamemode, room_id);
    
    // 2. If we are host (teammodel is null), fetch data asynchronously
    if (widget.teammodel == null) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoadingData = true;
    });
    
    print("DEBUG: Host starting async load for league: ${widget.gamemode}");
    try {
      final result = await ApiService.getLeagueInfo(widget.gamemode);
      if (result != null && mounted) {
        setState(() {
          widget.teammodel = result;
          _isLoadingData = false;
        });

        // Update WebSocketManager with the newly loaded data
        WebSocketManager().teammodel = result;
        
        // Push the fetched data to the guest via WebSocket
        WebSocketManager().syncTeamModel(result, widget.gamemode, widget.roundCount ?? 1);
      }
    } catch (e) {
      print("DEBUG: Error loading league data: $e");
      if (mounted) {
         setState(() {
          _isLoadingData = false;
        });
        // We might want to show an error or retry
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Deep Space Background
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
          
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Spacer(flex: 2), // Push content down below logo
                // Sized Box for extra measure if needed
                SizedBox(height: 50),

                // Premium Room Code "Ticket"
                SizedBox(height: 50),

                // Premium Room Code "Ticket"
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 40, vertical: 25),
                  decoration: BoxDecoration(
                    color: Color(0xFF1A1A2E).withOpacity(0.95),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.cyanAccent.withOpacity(0.5),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyanAccent.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        "ROOM CODE",
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          letterSpacing: 3.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        widget.room_id,
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 5.0,
                          shadows: [
                            Shadow(
                              color: Colors.purpleAccent,
                              blurRadius: 15,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 60),
                
                // Animated Waiting Text
                Column(
                  children: [
                    Stack(
                      children: [
                        Text(
                          "WAITING FOR PLAYER...",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            foreground: Paint()
                              ..style = PaintingStyle.stroke
                              ..strokeWidth = 3
                              ..color = Colors.white.withOpacity(0.3),
                          ),
                        ),
                        ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: [Colors.white, Colors.white70],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ).createShader(bounds),
                          child: Text(
                            "WAITING FOR PLAYER...",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
                    SizedBox(height: 30),
                    _BouncingFootballs(),
                    if (_isLoadingData) ...[
                      SizedBox(height: 20),
                      Text(
                        "FETCHING LEAGUE DATA...",
                        style: TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ],
                  ],
                ),
                
                Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 40.0),
                  child: Text(
                    "Share this code to start the match!",
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
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
}

class _BouncingFootballs extends StatefulWidget {
  @override
  _BouncingFootballsState createState() => _BouncingFootballsState();
}

class _BouncingFootballsState extends State<_BouncingFootballs>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            // Stagger animations
            double delay = i * 0.2;
            double value = (_controller.value + delay) % 1.0;
            
            // Sine wave calculation for smooth bounce
            // value goes 0 -> 1. We want a bounce (0 -> 1 -> 0)
            double bounce = Math.sin(value * Math.pi); // 0 at start, 1 at mid, 0 at end
            
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Column(
                children: [
                  // Bouncing Ball
                  Transform.translate(
                    offset: Offset(0, -20 * bounce), // Jump up 20 pixels
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.3 * bounce), // Glow at peak
                            blurRadius: 10 * bounce,
                            spreadRadius: 2 * bounce,
                          )
                        ]
                      ),
                      child: Icon(
                        Icons.sports_soccer,
                        color: Colors.white,
                        size: 32, // Magnificent size
                      ),
                    ),
                  ),
                  SizedBox(height: 5),
                  // Dynamic Shadow (Shrinks when ball goes up)
                  Opacity(
                    opacity: 1.0 - (bounce * 0.7), // Fades as ball goes up
                    child: Transform.scale(
                      scale: 1.0 - (bounce * 0.5), // Shrinks as ball goes up
                      child: Container(
                        width: 20,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}
