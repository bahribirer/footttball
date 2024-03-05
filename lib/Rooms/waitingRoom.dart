import 'dart:convert';

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

  
  String firstMessage="";
  bool control=true;

  @override
  void initState() {
    super.initState();
    var room_id=widget.room_id;
    // Initialize the WebSocketChannel in initState using widget.room_id
    WebSocketManager().connect('ws://172.20.10.2:8000/ws/$room_id', context, widget.teammodel, widget.gamemode,room_id);
    WebSocketManager().send(jsonEncode({"teammodel":widget.teammodel,"gamemode":widget.gamemode}));
  //   channel.stream.listen((message) {
  //   setState(() {
  //     if(control){
  //       firstMessage=message;
  //       control=false;
  //     }
      
      
  //     if(message=="ready"){
  //       Map<String, dynamic> decoded = jsonDecode(firstMessage);

        
  //       widget.teammodel.nations=List<String>.from(decoded["teammodel"]["nations"]);
  //       widget.teammodel.clubs=List<String>.from(decoded["teammodel"]["clubs"]);
  //       widget.gamemode=decoded["gamemode"];
        
  //        Navigator.push(
  //                  context,
  //                  MaterialPageRoute(builder: (context) => TikiTakaToeGame(teammodel:widget.teammodel, gamemode:widget.gamemode)),
  //               );
  //     }
  //     else {

  //     }
  //     // Process the incoming message
      
  //   });
  // });
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