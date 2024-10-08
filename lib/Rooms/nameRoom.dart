import 'dart:async';
import 'package:flutter/material.dart';
import 'package:footttball/Helper/loading.dart'; // loading.dart dosyasını dahil edin
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
          // Background image
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('images/arka2.PNG'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Name Input Field
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
          // Play Button
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
          // Loading Indicator
          if (_isLoading)
            CustomLoadingIndicator(), // Burada loading.dart'taki animasyonu çağırıyoruz
        ],
      ),
    );
  }

  void _navigateToStartPage() {
    if (_nameController.text.isEmpty) {
      _showNameNotEnteredDialog(context);
    } else {
      setState(() {
        _isLoading = true;
      });

      Timer(Duration(seconds: 3), () {
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
  }

  void _showNameNotEnteredDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Please Enter Name'),
          content: Text('You need to enter a name to proceed.'),
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

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
