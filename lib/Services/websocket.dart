import 'dart:async';
import 'dart:convert';
import 'package:footttball/Models/teamModel.dart';
import 'package:footttball/home.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/material.dart';

class WebSocketManager {
  WebSocketChannel? _channel;
  StreamController? _controller;
  bool control=true;
  String firstMessage="";

  int index=0;
  String type="";

  String initialType="";
  bool playerTurn=false;

  Function(int index,String type)? makeMove;

  static final WebSocketManager _instance = WebSocketManager._internal();

  factory WebSocketManager() {
    return _instance;
  }

  WebSocketManager._internal() {
    _controller = StreamController.broadcast();
  }

  void connect(String url,BuildContext context,TeamModel teammodel,String gamemode) {
    _channel = WebSocketChannel.connect(Uri.parse(url));
    _channel!.stream.listen((message) {
      if(control){
        firstMessage=message;
        control=false;
      }
      
      
      if(message=="ready"){
        Map<String, dynamic> decoded = jsonDecode(firstMessage);

        
        teammodel.nations=List<String>.from(decoded["teammodel"]["nations"]);
        teammodel.clubs=List<String>.from(decoded["teammodel"]["clubs"]);
        gamemode=decoded["gamemode"];
        
         Navigator.push(
                   context,
                   MaterialPageRoute(builder: (context) => TikiTakaToeGame(teammodel:teammodel, gamemode:gamemode)),
                );
      }
      else {

        if(message!="X" && message!="O"){
           Map<String,dynamic> decoded=jsonDecode(message);

        if(decoded.containsKey("index")){
          index=decoded["index"];
          type=decoded["type"];


        makeMove!(index,type);

        }

        }
        else {
          initialType=message;
          if(initialType=="X"){
            playerTurn=true;
          }
          else {
            playerTurn=false;
          }

        }

       
        

        
      }
    });
  }

  void send(String message) {
    _channel?.sink.add(message);
  }

  Stream get messages => _controller!.stream;

  void close() {
    _channel?.sink.close();
    _controller?.close();
  }
  
}
