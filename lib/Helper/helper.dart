import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:footttball/Services/api_service.dart';
import 'package:footttball/Helper/constants.dart';
import 'package:footttball/Services/websocket.dart';
import 'package:footttball/UI/modern_search_dialog.dart';

class Helper {
  Helper._privateConstructor();
  static final Helper _instance = Helper._privateConstructor();

  factory Helper() {
    return _instance;
  }

  TextEditingController playerName = TextEditingController();

  Future<bool?> showPlayerName(
      BuildContext context, String club, String nationality) async {
    playerName.text = "";

    final selectedPlayerName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return ModernSearchDialog(nationality: nationality, club: club);
      },
    );

    // User cancelled the dialog
    if (selectedPlayerName == null || selectedPlayerName.isEmpty) {
      return null; // null = cancelled, player keeps their turn
    }

    playerName.text = selectedPlayerName;
    
    var result = await ApiService.checkPlayer(
        player_name: selectedPlayerName,
        nationality: nationality,
        club: club);

    if (result == "true") {
      return true; // correct guess
    }
    return false; // wrong guess — turn switches
  }

  void showInfoDialog(BuildContext context, String title, String body, {VoidCallback? onDismiss}) {
    // Determine emoji and colors based on content
    String emoji = title.contains("SERIES") ? "🏆" : (title.contains("BERABERE") ? "🤝" : "⚽");
    bool isSeriesOver = title.contains("SERIES");
    bool isDraw = title.contains("BERABERE");
    
    showGeneralDialog(
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: Duration(milliseconds: 400),
      pageBuilder: (ctx, anim1, anim2) =>
          StatefulBuilder(builder: (context, setState) {
        return Center(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 30),
            padding: EdgeInsets.zero,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isSeriesOver
                    ? [Color(0xFF6A11CB), Color(0xFF2575FC)]
                    : (isDraw 
                        ? [Color(0xFF232526), Color(0xFF414345)] // Silver/Dark for Draw
                        : [Color(0xFF0F2027), Color(0xFF2C5364)]),
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSeriesOver
                      ? Colors.purpleAccent.withOpacity(0.5)
                      : (isDraw 
                          ? Colors.white.withOpacity(0.2) 
                          : Colors.cyanAccent.withOpacity(0.3)),
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
                  // Emoji
                  Text(
                    emoji,
                    style: TextStyle(fontSize: isSeriesOver ? 56 : 44),
                  ),
                  SizedBox(height: 12),
                  // Title
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      shadows: [
                        Shadow(
                          blurRadius: 12,
                          color: Colors.white.withOpacity(0.5),
                          offset: Offset(0, 0),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  // Body
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      body,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                  SizedBox(height: 24),
                  // Button
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
                            isSeriesOver ? "🎮  NEW GAME" : (isDraw ? "▶  NEXT ROUND" : "▶  NEXT ROUND"),
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
        );
      }),
      transitionBuilder: (ctx, anim1, anim2, child) => BackdropFilter(
        filter:
            ImageFilter.blur(sigmaX: 6 * anim1.value, sigmaY: 6 * anim1.value),
        child: ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
          child: FadeTransition(
            opacity: anim1,
            child: child,
          ),
        ),
      ),
      context: context,
    ).then((_) {
      if (onDismiss != null) {
        onDismiss();
      }
    });
  }
}
