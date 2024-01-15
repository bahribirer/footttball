// ignore_for_file: unused_element

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:footttball/players.dart';
import 'api_service.dart';
import 'splash.dart';
import 'main.dart';

void main() {
  runApp(const TikiTakaToeApp());
}

class TikiTakaToeApp extends StatelessWidget {
  const TikiTakaToeApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tiki Taka Toe',
      home: StartPage(),
    );
  }
}

class StartPage extends StatelessWidget {
  const StartPage({Key? key}) : super(key: key);

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
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => CreateRoomPage()),
                );
              },
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
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => JoinRoomPage()),
                );
              },
              child: Image.asset(
                'images/join.PNG',
                width: MediaQuery.of(context).size.width * 0.4,
                height: MediaQuery.of(context).size.height * 0.2,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
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
class CreateRoomPage extends StatefulWidget {
  @override
  _CreateRoomPageState createState() => _CreateRoomPageState();
}

class _CreateRoomPageState extends State<CreateRoomPage> {
  String selectedGameMode = ''; // Seçilen oyun modu
  late String roomCode;
  late bool isLeagueSelected;
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
    apiService = ApiService('http://127.0.0.1:8000');
  }

  String _generateRandomCode() {
    var random = Random();
    int randomCode = 1000 + random.nextInt(9000);
    return randomCode.toString();
  }

  Future<void> _startGame() async {
  if (selectedGameMode.isNotEmpty) {
    try {
      // Oyun moduna göre lig bilgilerini alma
      final leagueInfo = await apiService.getLeagueInfo(selectedGameMode);
      print('League Information: $leagueInfo');

      // Lig bilgilerini kullanarak oyuncu listesini ve ülkeleri alma
      final result = await apiService.getPlayersAndCountriesByLeague(leagueInfo);
      final players = result['players'] as List<Player>;
      final countries = result['countries'] as List<String>;

      print('Players in the selected league: $players');
      print('Countries in the selected league: $countries');

      // Oyuncu listesi ve ülkeleri kullanarak oyunu başlatma işlemleri burada yapılacak
      _startGameScreen(players, countries);
    } catch (e) {
      print('Error fetching league information: $e');
    }
  } else {
    _showModeNotSelectedDialog(context);
  }
}



  void _startGameScreen(List<Player> players, List<String> countries) {
    // Oyun ekranına geçiş yapmak için Navigator kullanma
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) {
          // Oyuncu listesi ve ülkeleri ileterek oyun sayfasına geçiş yapma
          return TikiTakaToeGame(
            gridInfo: {'players': players, 'countries': countries},
          );
        },
      ),
    );
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
        primary: Colors.transparent,
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
        return AlertDialog(
          title: Text('Please Choose The Mode'),
          backgroundColor: Color.fromARGB(255, 210, 147, 221),
          content:
              Text('You need to choose a game mode before starting the game.'),
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

  void _showGameModeSelectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Select Game Mode'),
          content: Container(
            height: 200,
            width: 200,
            child: Wrap(
              spacing: 10.0,
              runSpacing: 10.0,
              children: [
                buildGameModeButton('images/eng.PNG', 'Premier League'),
                buildGameModeButton('images/fran.PNG', 'Ligue1'),
                buildGameModeButton('images/isp.PNG', 'LaLiga'),
                buildGameModeButton('images/ger.PNG', 'Bundesliga'),
                buildGameModeButton('images/tr.PNG', 'Super League'),
                buildGameModeButton('images/seri.PNG', 'Serie A'),
                buildGameModeButton('images/rand.PNG', 'Random'),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null,
      body: Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('images/arka1.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: -20,
                  child: GestureDetector(
                    onTap: () {
                      _showGameModeSelectionDialog(context);
                    },
                    child: Text(
                      selectedGameMode.isNotEmpty
                          ? 'Selected Game Mode: $selectedGameMode'
                          : 'Choose Game Mode',
                      style: TextStyle(
                        color: Color.fromARGB(255, 0, 10, 0),
                        fontSize: 16,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      Text(
                        'ROOM CODE: $roomCode',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 150),
            Column(
              children: [
                buildGameModeButton('images/eng.PNG', 'Premier League'),
                buildGameModeButton('images/fran.PNG', 'Ligue1'),
                buildGameModeButton('images/isp.PNG', 'LaLiga'),
                buildGameModeButton('images/ger.PNG', 'Bundesliga'),
                buildGameModeButton('images/tr.PNG', 'Super League'),
                buildGameModeButton('images/seri.PNG', 'Serie A'),
                buildGameModeButton('images/rand.PNG', 'Random'),
              ],
            ),
            SizedBox(height: 30),
            ElevatedButton(
              onPressed: _startGame,
              style: ElevatedButton.styleFrom(
                primary: Colors.transparent,
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
    );
  }

}





class JoinRoomPage extends StatefulWidget {
  @override
  _JoinRoomPageState createState() => _JoinRoomPageState();
}

class _JoinRoomPageState extends State<JoinRoomPage> {
  String? roomCode;
  String selectedGameMode = ''; // Seçilen oyun modu
  late FocusNode _roomCodeFocusNode;

  @override
  void initState() {
    super.initState();
    _roomCodeFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _roomCodeFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Join Room'),
        backgroundColor: Colors.blue,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              maxLength: 4,
              keyboardType: TextInputType.number,
              onChanged: (value) {
                setState(() {
                  roomCode = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Enter Room Code',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(vertical: 10, horizontal: 15),
              ),
            ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget buildGameModeButton(String mode) {
    return ElevatedButton(
      onPressed: () {
        setState(() {
          selectedGameMode = mode;
        });
      },
      style: ElevatedButton.styleFrom(
        primary: Colors.blue,
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      ),
      child: Text(mode),
    );
  }

  void _showCodeNotSelectedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Please Enter Code'),
          content: Text('You need to enter code.'),
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
}
