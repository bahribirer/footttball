// ignore_for_file: unused_element

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:footttball/Models/teamModel.dart';
import 'package:footttball/Rooms/waitingRoom.dart';
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

class _JoinRoomPageState extends State<JoinRoomPage> {
  String? roomCode;
  String selectedGameMode = ''; // Seçilen oyun modu
  late FocusNode _roomCodeFocusNode;
  TextEditingController roomcode = new TextEditingController();

  @override
  void initState() {
    super.initState();
    _roomCodeFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _roomCodeFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Join Room'),
        backgroundColor: Colors.blue,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: roomcode,
              decoration: InputDecoration(hintText: "Enter Room Code"),
            ),
            SizedBox(height: 20),
            TextButton(
              child: Text('OK'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => WaitingRoom(
                          room_id: roomcode.text,
                          teammodel: TeamModel(nations: [""], clubs: [""]),
                          gamemode: "")),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget buildGameModeButton(String mode) {
    return ElevatedButton(
      onPressed: () {
        setState(() {
          selectedGameMode = mode;
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      ),
      child: Text(mode),
    );
  }

  void _showCodeNotSelectedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Please Enter Code'),
          content: Text('You need to enter code.'),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }
}

// void main() {
//   runApp(const TikiTakaToeApp());
// }

// class TikiTakaToeApp extends StatelessWidget {
//   const TikiTakaToeApp({Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Tiki Taka Toe',
//       home: StartPage(),
//     );
//   }
// }


// class BackgroundWidget extends StatelessWidget {
//   const BackgroundWidget({Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return Positioned.fill(
//       child: Image.asset(
//         'images/arka1.png',
//         fit: BoxFit.cover,
//       ),
//     );
//   }
// }



