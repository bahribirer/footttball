import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
import 'package:footttball/Api/api_service.dart';
import 'package:footttball/Helper/helper.dart';
import 'package:footttball/Models/teamModel.dart';
import 'package:footttball/getInfo.dart';
import 'package:footttball/home.dart';
import 'package:footttball/main.dart';
import 'package:footttball/Models/players.dart';
import 'package:footttball/startPage.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';


class WaitingRoom extends StatefulWidget {
  String room_id;
  TeamModel teammodel;
  String gamemode;
   WaitingRoom({super.key,required this.room_id,required this.teammodel,required this.gamemode});

  @override
  State<WaitingRoom> createState() => _WaitingRoomState();
}

class _WaitingRoomState extends State<WaitingRoom> {

  
  late final WebSocketChannel channel;

  @override
  void initState() {
    super.initState();
    var room_id=widget.room_id;
    // Initialize the WebSocketChannel in initState using widget.room_id
    channel = WebSocketChannel.connect(
      Uri.parse('ws://192.168.0.11:8000/ws/$room_id'),
    );
    channel.sink.add("HELLO ROOM");
    channel.stream.listen((message) {
    setState(() {
      if(message=="ready"){
        Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => TikiTakaToeGame(teammodel:widget.teammodel, gamemode:widget.gamemode)),
                );
      }
      // Process the incoming message
      
    });
  });
  }
  void _sendMessage(String message) {
  channel.sink.add(message);
}


  @override
  Widget build(BuildContext context) {
    Size screenSize = MediaQuery.of(context).size;
    double boxSize = screenSize.width / 4 * 0.8;
    return Scaffold(
      appBar: null,
      body: Stack(
        alignment: Alignment.center,
        children: [
          BackgroundWidget(),
          
          Center(
            child:Column(
              mainAxisSize:MainAxisSize.min,
              children: [
                Text(
              'Waiting For Other Player to Join!',
              style: TextStyle(fontSize: 24, color: Colors.white),
            ),
            SizedBox(height: 200,),

            CircularProgressIndicator(
              color:Colors.white,
            
            )
              ],
            ),
          )

          
          
         
          
        ],
      ),
    );
  }
}