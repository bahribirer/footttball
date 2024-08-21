import 'dart:math';
import 'package:flutter/material.dart';
import 'package:footttball/Services/api_service.dart';
import 'package:footttball/Models/teamModel.dart';
import 'package:footttball/Rooms/waitingRoom.dart';
import 'package:footttball/Rooms/startPage.dart'; // Import StartPage to navigate back
import 'package:footttball/getInfo.dart';
import 'package:footttball/home.dart';
import 'package:footttball/main.dart';
import 'package:footttball/Models/players.dart';

class CreateRoomPage extends StatefulWidget {
  @override
  _CreateRoomPageState createState() => _CreateRoomPageState();
}

class _CreateRoomPageState extends State<CreateRoomPage> {
  String selectedGameMode = ''; // Seçilen oyun modu
  late String roomCode;
  late bool isLeagueSelected;
  var teamobject = getTeamInfo();

  Map<String, bool> isModeSelectedMap = {
    'Premier League': false,
    'Ligue1': false,
    'LaLiga': false,
    'Bundesliga': false,
    'Super League': false,
    'Serie A': false,
    'Random': false,
  };
  late ApiService apiService;

  @override
  void initState() {
    super.initState();
    isLeagueSelected = false;
    roomCode = _generateRandomCode();
    teamobject = getTeamInfo();
  }

  String _generateRandomCode() {
    var random = Random();
    int randomCode = 1000 + random.nextInt(9000);
    return randomCode.toString();
  }

  Widget buildGameModeButton(String imagePath, String mode) {
    return ElevatedButton(
      onPressed: () {
        setState(() {
          selectedGameMode = mode;
          isModeSelectedMap.forEach((key, value) {
            isModeSelectedMap[key] = (key == mode);
          });
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        padding: EdgeInsets.all(0),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Ink.image(
            image: AssetImage(imagePath),
            fit: BoxFit.contain,
            width: MediaQuery.of(context).size.width * 0.7,
            height: MediaQuery.of(context).size.height * 0.07,
            child: InkWell(),
          ),
          if (isModeSelectedMap[mode]!)
            Positioned(
              right: 8.0,
              child: Image.asset(
                'images/ok.PNG',
                width: 24.0,
                height: 24.0,
              ),
            ),
        ],
      ),
    );
  }

  void _showModeNotSelectedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.transparent,
          child: _AnimatedExclamationDialog(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('images/arka1.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Back Button Positioned
          Positioned(
            top: 40,
            left: 20,
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => StartPage()),
                );
              },
              child: Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.arrow_back,
                  size: 30,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          // Main Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 50),
                // Positioned ROOM CODE just above Premier League
                Text(
                  'ROOM CODE: $roomCode',
                  style: TextStyle(
                    color: const Color.fromARGB(255, 232, 234, 233),
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                    shadows: [
                      Shadow(
                        blurRadius: 5.0,
                        color: Colors.black45,
                        offset: Offset(2.0, 2.0),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 10),
                Column(
                  children: [
                    buildGameModeButton('images/eng.PNG', 'Premier League'),
                    buildGameModeButton('images/fran.PNG', 'Ligue1'),
                    buildGameModeButton('images/isp.PNG', 'LaLiga'),
                    buildGameModeButton('images/ger.PNG', 'Bundesliga'),
                    buildGameModeButton('images/tr.PNG', 'Super League'),
                    buildGameModeButton('images/seri.PNG', 'Serie A'),
                  ],
                ),
                SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () async {
                    if (selectedGameMode.isEmpty) {
                      _showModeNotSelectedDialog(context);
                    } else {
                      print(selectedGameMode);
                      var result = await ApiService.getLeagueInfo(
                          teamobject.getmap(selectedGameMode));
                      print(result);

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => WaitingRoom(
                            room_id: roomCode,
                            teammodel: result!,
                            gamemode: teamobject.getmap(selectedGameMode),
                          ),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    padding: EdgeInsets.zero,
                  ),
                  child: Ink.image(
                    image: AssetImage('images/play.PNG'),
                    fit: BoxFit.contain,
                    width: MediaQuery.of(context).size.width * 0.46,
                    height: MediaQuery.of(context).size.height * 0.1,
                    child: InkWell(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedExclamationDialog extends StatefulWidget {
  @override
  __AnimatedExclamationDialogState createState() =>
      __AnimatedExclamationDialogState();
}

class __AnimatedExclamationDialogState extends State<_AnimatedExclamationDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ScaleTransition(
            scale: _animation,
            child: Icon(
              Icons.warning_amber_rounded,
              size: 50,
              color: Colors.redAccent,
            ),
          ),
          SizedBox(height: 15),
          Text(
            "Please Choose The Mode",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 15),
          Text(
            "You need to choose a game mode before starting the game.",
            style: TextStyle(
              fontSize: 16,
              color: Colors.black54,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 25),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.redAccent, // text color
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Text(
                "OK",
                style: TextStyle(
                  fontSize: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
