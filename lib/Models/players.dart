
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:footttball/Models/players.dart';
import '../Api/api_service.dart';
import '../splash.dart';
import '../main.dart';


class Player {
  String name;
  String nationality;
  String club;

  Player({
    required this.name,
    required this.nationality,
    required this.club,
  });

  // JSON'dan Player nesnesi oluşturmak için fromJson metodu
  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      name: json['name'],
      nationality: json['nationality'],
      club: json['club'],
    );
  }
}
