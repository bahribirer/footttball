// NameRoom.dart

import 'package:flutter/material.dart';
import 'package:footttball/Rooms/startPage.dart';

class NameRoom extends StatefulWidget {
  const NameRoom({Key? key}) : super(key: key);

  @override
  _NameRoomState createState() => _NameRoomState();
}

class _NameRoomState extends State<NameRoom> {
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
          // İsim giriş kutusu
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
          // Görüntü ve Gesture Detector
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.05,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () {
                  // İsim kutusu boşsa uyarı göster
                  if (_nameController.text.isEmpty) {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: Text('Warning'),
                          content: Text('Please Enter Your Name!'),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: Text('Okay'),
                            ),
                          ],
                        );
                      },
                    );
                  } else {
                    // İsim kutusu doluysa oyun sayfasına git ve ismi ileteceğiz
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => StartPage(),
                      ),
                    );
                  }
                },
                child: Image.asset(
                  'images/play.PNG',
                  width: MediaQuery.of(context).size.width * 0.4,
                  height: MediaQuery.of(context).size.height * 0.2,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
