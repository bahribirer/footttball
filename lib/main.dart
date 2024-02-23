import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:footttball/home.dart';
import 'package:footttball/players.dart';
import 'package:footttball/joinRoom.dart';
import 'package:footttball/startPage.dart';
import 'api_service.dart';
import "players.dart";

void main() {
  runApp(const TikiTakaToeApp(gridInfo: {}));
}

class TikiTakaToeApp extends StatelessWidget {
  const TikiTakaToeApp({Key? key, required this.gridInfo}) : super(key: key);
  final Map<String, dynamic> gridInfo;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: StartPage(),
    );
  }
}


class BackgroundWidget extends StatelessWidget {
  const BackgroundWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Image.asset(
        'images/arka1.png',
        fit: BoxFit.cover,
      ),
    );
  }
}
