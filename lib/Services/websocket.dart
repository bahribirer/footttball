import 'dart:async';
import 'dart:convert';
import 'package:footttball/Helper/helper.dart';
import 'package:footttball/Models/teamModel.dart';
import 'package:footttball/Rooms/startPage.dart';
import 'package:footttball/home.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/material.dart';
import 'package:footttball/Services/api_service.dart';
import 'package:footttball/Rooms/vs_screen.dart'; // Import VsScreen
import 'package:footttball/Helper/globals.dart' as globals;

class WebSocketManager {
  WebSocketChannel? _channel;
  StreamController? _controller;
  TeamModel? teammodel; // Manage teammodel centrally
  bool control = true;
  String firstMessage = "";
  String? _requestingPlayer;

  int index = 0;
  String type = "";

  String initialType = "";
  bool playerTurn = false;
  
  // Cache for names
  String p1Name = "Player 1";
  String p2Name = "Player 2";

  Function(int index, String type, String? playerName)? makeMove;
  Function()? onReplayRequest;
  Function()? onReplayAccept;
  Function()? onReplayDataReceived;
  Function()? onPlayerLeave;
  Function()? onReplayDeclined;
  Function(String name, String type)? onNameAnnounced; // Callback for name syncing
  Function(int seconds)? onTimerSync; // Callback for timer syncing
  Function(int index)? onCellSelected; // Callback for opponent selection
  Function()? onNextRoundRequest;
  Function(Map<String, dynamic> data)? onNextRoundData;

  static final WebSocketManager _instance = WebSocketManager._internal();

  factory WebSocketManager() {
    return _instance;
  }

  WebSocketManager._internal() {
    _controller = StreamController.broadcast();
  }

  void connect(String url, BuildContext context, TeamModel? teammodel,
      String gamemode, String room_id) {
    // Reset State for new game
    control = true;
    firstMessage = "";
    p1Name = "Player 1";
    p2Name = "Player 2";
    playerTurn = false;
    _requestingPlayer = null;
    this.teammodel = teammodel; // Store reference if provided (usually for Host)

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

        // Initialize or update teammodel from the setup message
        if (teammodel == null) {
          teammodel = TeamModel.fromJson(decoded["teammodel"]);
        } else {
          teammodel!.nations = List<String>.from(decoded["teammodel"]["nations"]);
          teammodel!.clubs = List<String>.from(decoded["teammodel"]["clubs"]);
        }
        
        gamemode = decoded["gamemode"];
        
        // Extract roundCount and creatorName (player1Name)
        int roundCount = decoded["roundCount"] ?? 1; // Default to 1 if missing
        print("DEBUG: Extracted roundCount: $roundCount");
        
        // Robust Name Extraction
        String p1NameFromData = decoded["name"] ?? "";
        String p2NameFromData = ""; // Logic to get P2 name if available in future
        
        // Fallback if names are empty
        String p1Display = p1NameFromData.isNotEmpty ? p1NameFromData : "Player 1";
        String p2Display = "Player 2"; // Placeholder until P2 name is sent by server



        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => VsScreen(
                    teammodel: teammodel!, // Safe now as it's initialized above if null
                    gamemode: gamemode,
                    player1Name: p1Display,
                    player2Name: p2Display,
                    roundCount: roundCount,
                  )),
        );
      } else if (message == "replayRequest") {
        // Notify client about the replay request so they can show the dialog
        if (onReplayRequest != null) {
          onReplayRequest!();
        }
      } else if (message.startsWith('{"type":"replayData"')) {
        // Apply the synced replay data
        Map<String, dynamic> decoded = jsonDecode(message);

        if (teammodel == null) {
          teammodel = TeamModel.fromJson(decoded);
        } else {
          teammodel!.nations = List<String>.from(decoded["nations"]);
          teammodel!.clubs = List<String>.from(decoded["clubs"]);
        }

        // Notify client to reset UI with new data
        if (onReplayDataReceived != null) {
          onReplayDataReceived!();
        }
      } else if (message == "leaveRoom") {
         if (onPlayerLeave != null) {
           onPlayerLeave!();
         }
      } else if (message == "replayDecline") {
        if (onReplayDeclined != null) {
          onReplayDeclined!();
        }
      } else if (message.startsWith('{"type":"selectCell"')) {
        Map<String, dynamic> decoded = jsonDecode(message);
        if (onCellSelected != null) {
          onCellSelected!(decoded["index"]);
        }
      } else if (message.startsWith('{"type":"deselectCell"')) {
        if (onCellSelected != null) {
          onCellSelected!(-1); // -1 indicates desclection
        }
      } else {
        if (message != "X" && message != "O") {
          Map<String, dynamic> decoded = jsonDecode(message);

          if (decoded.containsKey("index")) {
            index = decoded["index"];
            type = decoded["type"];
            String? playerName = decoded["playerName"]; // Extract player name

            makeMove!(index, type, playerName);
          } else if (decoded["type"] == "requestNextRound") {
            if (onNextRoundRequest != null) {
              onNextRoundRequest!();
            }
          } else if (decoded["type"] == "nextRoundData") {
            if (onNextRoundData != null) {
              onNextRoundData!(decoded);
            }
          } else if (decoded["type"] == "announceName") {
            // Handle name announcement
            String name = decoded["name"];
            String playerType = decoded["playerType"];
            
            // Cache the name
            if (playerType == "X") { // Assuming X is P1, needs verification or dynamic assignment
               p1Name = name;
            } else {
               p2Name = name;
            }

            if (onNameAnnounced != null) {
              onNameAnnounced!(name, playerType);
            }
          } else if (decoded["type"] == "timerSync") {
            // Handle timer sync from the active player
            if (onTimerSync != null) {
              onTimerSync!(decoded["seconds"]);
            }
          }
        } else {
          initialType = message;
          playerTurn = (initialType == "X");
        }
      }
    });
  }

  void syncTeamModel(TeamModel teammodel, String gamemode, int roundCount) {
     final data = {
      "teammodel": {
        "nations": teammodel.nations,
        "clubs": teammodel.clubs,
      },
      "gamemode": gamemode,
      "roundCount": roundCount,
      "name": globals.player1Name,
    };
    send(jsonEncode(data));
    print("DEBUG: Host synced TeamModel via WebSocket");
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
