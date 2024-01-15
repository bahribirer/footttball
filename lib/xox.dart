/*import 'dart:convert';
import 'package:flutter/material.dart';
import 'api_service.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<String> gridNations = [];
  List<String> gridClubs = [];
  final ApiService apiService = ApiService('http://127.0.0.1:8000');

  @override
  void initState() {
    super.initState();
    fetchGridInformation();
  }

  Future<void> fetchGridInformation() async {
    try {
      final data = await apiService.getGridInformation();
      setState(() {
        gridNations = List<String>.from(data['grid_nations']);
        gridClubs = List<String>.from(data['grid_clubs']);
      });
    } catch (e) {
      print('Error: $e');
    }
  }

  Future<void> makeGuess(String playerName) async {
    try {
      final data = await apiService.makeGuess(
        playerName,
        gridNations.isNotEmpty ? gridNations[0] : '',
        gridClubs.isNotEmpty ? gridClubs[0] : '',
      );

      if (data['guess_result']) {
        print('Correct guess!');
      } else {
        print('Wrong guess!');
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Flutter - FastAPI Communication'),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Grid Nations: ${gridNations.join(', ')}'),
          Text('Grid Clubs: ${gridClubs.join(', ')}'),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => makeGuess('John Doe'),
            child: Text('Make Guess'),
          ),
        ],
      ),
    );
  }
}*/
