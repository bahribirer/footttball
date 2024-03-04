import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:footttball/Services/api_service.dart';
import 'package:footttball/Helper/constants.dart';

class Helper {
  Helper._privateConstructor();
  static final Helper _instance = Helper._privateConstructor();

  factory Helper() {
    return _instance;
  }

  double getDeviceWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  double getDeviceHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }

  TextEditingController playerName = new TextEditingController();

  void showInfoDialog(BuildContext context, String title, String body) {
    showGeneralDialog(
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black38,
      transitionDuration: Duration(milliseconds: 500),
      pageBuilder: (ctx, anim1, anim2) =>
          StatefulBuilder(builder: (context, setState) {
        return Container(
          height: Helper().getDeviceHeight(context) / 4,
          child: AlertDialog(
            backgroundColor: Constants().textColor,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16.0))),
            title: Text(
              title,
              style: TextStyle(color: Constants().blackTextColor),
            ),
            content: Text(body,
                style:
                    TextStyle(color: Constants().blackTextColor, fontSize: 15)),
            elevation: 2,
          ),
        );
      }),
      transitionBuilder: (ctx, anim1, anim2, child) => BackdropFilter(
        filter:
            ImageFilter.blur(sigmaX: 4 * anim1.value, sigmaY: 4 * anim1.value),
        child: FadeTransition(
          child: child,
          opacity: anim1,
        ),
      ),
      context: context,
    );
  }

  Future<bool> showPlayerName(
    
      BuildContext context, String club, String nationality) async {
        playerName.text="";
    Completer<bool> completer = Completer<bool>();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(nationality + " " + club),
          content: TextField(
            controller: playerName,
            decoration: InputDecoration(hintText: "Enter Player Name"),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('OK'),
              onPressed: () async {
                var result = await ApiService.checkPlayer(
                    player_name: playerName.text,
                    nationality: nationality,
                    club: club);
                if (result == "true") {
                  completer.complete(true);
                } else {
                  completer.complete(false);
                }

                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
    return completer.future;
  }
}
