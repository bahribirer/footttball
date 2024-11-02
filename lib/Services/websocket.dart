import 'dart:async';
import 'dart:convert';
import 'package:footttball/Helper/helper.dart';
import 'package:footttball/Models/teamModel.dart';
import 'package:footttball/Rooms/startPage.dart';
import 'package:footttball/home.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/material.dart';
import 'package:footttball/Services/api_service.dart';

class WebSocketManager {
  WebSocketChannel? _channel;
  StreamController? _controller;
  bool control = true;
  String firstMessage = "";
  String? _requestingPlayer;

  int index = 0;
  String type = "";

  String initialType = "";
  bool playerTurn = false;

  Function(int index, String type)? makeMove;
  Function()? onReplayRequest;
  Function()? onReplayAccept;
  Function()? onPlayerLeave;

  static final WebSocketManager _instance = WebSocketManager._internal();

  factory WebSocketManager() {
    return _instance;
  }

  WebSocketManager._internal() {
    _controller = StreamController.broadcast();
  }

  void connect(String url, BuildContext context, TeamModel teammodel,
      String gamemode, String room_id) {
    _channel = WebSocketChannel.connect(Uri.parse(url));
    _channel!.stream.listen((message) async {
      if (control) {
        firstMessage = message;
        control = false;
      }

      if (message == "A player has left the room $room_id.") {
        if (onPlayerLeave != null) {
          onPlayerLeave!();
        }
      } else if (message == "ready") {
        Map<String, dynamic> decoded = jsonDecode(firstMessage);

        teammodel.nations = List<String>.from(decoded["teammodel"]["nations"]);
        teammodel.clubs = List<String>.from(decoded["teammodel"]["clubs"]);
        gamemode = decoded["gamemode"];

        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => TikiTakaToeGame(
                    teammodel: teammodel,
                    gamemode: gamemode,
                    player1Name: '',
                    player2Name: '',
                  )),
        );
      } else if (message == "replayRequest") {
        // Broadcast a request for replay data to the server
        send("requestReplayData");

        // Notify both clients about the replay request
        if (onReplayRequest != null) {
          onReplayRequest!();
        }
      } else if (message == "replayAccept") {
        // When replay is accepted, request updated data for all clients
        send("requestReplayData");

        // Notify both clients about replay acceptance
        if (onReplayAccept != null) {
          onReplayAccept!();
        }
      } else if (message.startsWith('{"type":"replayData"')) {
        // Parse and apply the replay data to ensure both clients update their UI
        Map<String, dynamic> decoded = jsonDecode(message);

        teammodel.nations = List<String>.from(decoded["nations"]);
        teammodel.clubs = List<String>.from(decoded["clubs"]);

        // Explicitly trigger the UI update on both clients
        if (onReplayAccept != null) {
          onReplayAccept!();
        }
      } else if (message == "leaveRoom") {
        if (onPlayerLeave != null) {
          onPlayerLeave!();
        }
      } else {
        if (message != "X" && message != "O") {
          Map<String, dynamic> decoded = jsonDecode(message);

          if (decoded.containsKey("index")) {
            index = decoded["index"];
            type = decoded["type"];

            makeMove!(index, type);
          }
        } else {
          initialType = message;
          playerTurn = (initialType == "X");
        }
      }
    });
  }

  void sendLeaveRoom() {
    send("leaveRoom");
  }

  void send(String message) {
    _channel?.sink.add(message);
  }

  Stream get messages => _controller!.stream;

  void close() {
    _channel?.sink.close();
    _controller?.close();
  }

  void sendReplayRequest() {
    send("replayRequest");
  }

  void sendReplayAccept() {
    send("replayAccept");
  }
}
