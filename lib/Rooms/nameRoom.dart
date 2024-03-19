import 'dart:async';

import 'package:flutter/material.dart';
import 'package:footttball/Rooms/startPage.dart';

class NameRoom extends StatefulWidget {
  const NameRoom({Key? key}) : super(key: key);

  @override
  _NameRoomState createState() => _NameRoomState();
}

class _NameRoomState extends State<NameRoom> {
  bool _isLoading = false;
  TextEditingController _nameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null,
      body: Stack(
        children: [
          // Arka plan görüntüsü
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('images/arka2.PNG'),
                fit: BoxFit.cover,
              ),
            ),
          ),

          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 150),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: 'Enter Name',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
          ),
          //media query
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.05,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isLoading ? null : _navigateToStartPage,
                child: Image.asset(
                  'images/play.PNG',
                  width: MediaQuery.of(context).size.width * 0.4,
                  height: MediaQuery.of(context).size.height * 0.2,
                  fit: BoxFit.contain,
                ),
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

  void _navigateToStartPage() {
    setState(() {
      _isLoading = true;
    });

    Timer(Duration(seconds: 1), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => StartPage(),
        ),
      );
      setState(() {
        _isLoading = false;
      });
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
