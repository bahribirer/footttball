import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:footttball/Services/api_service.dart';
import 'package:footttball/Helper/constants.dart';
import 'package:footttball/Services/websocket.dart';

class Helper {
  Helper._privateConstructor();
  static final Helper _instance = Helper._privateConstructor();

  factory Helper() {
    return _instance;
  }

  TextEditingController playerName = TextEditingController();

  Future<bool> showPlayerName(
      BuildContext context, String club, String nationality) async {
    playerName.text = "";
    Completer<bool> completer = Completer<bool>();

    WebSocketManager wsManager = WebSocketManager();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(nationality + " " + club),
          content: Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) async {
              if (textEditingValue.text == '') {
                return const Iterable<String>.empty();
              }
              List<String> playerNames = await ApiService()
                  .getPlayerNames(query: textEditingValue.text);
              print('Autocomplete Names: $playerNames');
              return playerNames;
            },
            onSelected: (String selection) {
              playerName.text = selection;
            },
            fieldViewBuilder:
                (context, controller, focusNode, onEditingComplete) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(hintText: "Enter Player Name"),
              );
            },
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
                  WebSocketManager().send(jsonEncode({
                    "index": WebSocketManager().index,
                    "type": WebSocketManager().type
                  }));
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

  void showInfoDialog(BuildContext context, String title, String body) {
    showGeneralDialog(
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black38,
      transitionDuration: Duration(milliseconds: 500),
      pageBuilder: (ctx, anim1, anim2) =>
          StatefulBuilder(builder: (context, setState) {
        return Container(
          height: MediaQuery.of(context).size.height / 4,
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
}
