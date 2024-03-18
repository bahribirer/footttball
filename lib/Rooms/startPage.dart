import 'dart:async';

import 'package:flutter/material.dart';
import 'package:footttball/Rooms/createRoom.dart';
import 'package:footttball/Rooms/joinRoom.dart';

class StartPage extends StatefulWidget {
  const StartPage({Key? key}) : super(key: key);

  @override
  _StartPageState createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null,
      body: Stack(
        children: [
          GestureDetector(
            onTap: () {
              // Herhangi bir yere tıklanınca buraya gelecek
            },
            child: Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('images/arka2.PNG'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Positioned(
            right: MediaQuery.of(context).size.width * 0.55,
            bottom: MediaQuery.of(context).size.height * 0.05,
            child: GestureDetector(
              onTap: _isLoading ? null : () => _navigateToCreateRoom(context),
              child: Image.asset(
                'images/create.PNG',
                width: MediaQuery.of(context).size.width * 0.4,
                height: MediaQuery.of(context).size.height * 0.2,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Positioned(
            left: MediaQuery.of(context).size.width * 0.55,
            bottom: MediaQuery.of(context).size.height * 0.05,
            child: GestureDetector(
              onTap: _isLoading ? null : () => _navigateToJoinRoom(context),
              child: Image.asset(
                'images/join.PNG',
                width: MediaQuery.of(context).size.width * 0.4,
                height: MediaQuery.of(context).size.height * 0.2,
                fit: BoxFit.contain,
              ),
            ),
          ),
          if (_isLoading)
            Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }

  void _navigateToCreateRoom(BuildContext context) {
    setState(() {
      _isLoading = true;
    });

    Timer(Duration(seconds: 1), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => CreateRoomPage(),
        ),
      );
      setState(() {
        _isLoading = false;
      });
    });
  }

  void _navigateToJoinRoom(BuildContext context) {
    setState(() {
      _isLoading = true;
    });

    Timer(Duration(seconds: 1), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => JoinRoomPage(),
        ),
      );
      setState(() {
        _isLoading = false;
      });
    });
  }
}
