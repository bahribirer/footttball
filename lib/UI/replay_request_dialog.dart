import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:footttball/Helper/constants.dart';

class ReplayRequestDialog extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const ReplayRequestDialog({
    Key? key,
    required this.onAccept,
    required this.onDecline,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Constants().backgroundColor.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            Text(
              "Rematch Request",
              style: TextStyle(
                color: Constants().titleColor,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 15),
            
            // Content
            Text(
              "Your opponent wants to play again.\nDo you accept the challenge?",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Constants().blackTextColor,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 25),
            
            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Decline Button
                TextButton(
                  onPressed: onDecline,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    backgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    "Decline",
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                
                // Accept Button
                ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    backgroundColor: Constants().buttonColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 5,
                  ),
                  child: Text(
                    "Accept",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
