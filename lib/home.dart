import 'package:flutter/material.dart';
import 'package:footttball/api_service.dart';
import 'package:footttball/main.dart';
import 'package:footttball/players.dart';
import 'package:footttball/startPage.dart';


class TikiTakaToeGame extends StatefulWidget {

  TikiTakaToeGame({Key? key}) : super(key: key);

  @override
  _TikiTakaToeGameState createState() => _TikiTakaToeGameState();
}



class _TikiTakaToeGameState extends State<TikiTakaToeGame> {
  late List<Player> players;
  late String currentPlayer;
  late ApiService apiService;
  late List<String> squares;
  @override
  void initState() {
    super.initState();
    resetGame();
    
  }

 void fetchAndShowGridInformation(String leagueId) async {
  // try {
  //   final leagueInfo = await apiService.getLeagueInfo(leagueId);
  //   final players = await apiService.getPlayersByLeague(leagueInfo);
  //   setState(() {
  //     this.players = players.map((playerData) => Player(
  //       name: playerData['name'],
  //       nationality: playerData['nationality'],
  //       club: playerData['club'],
  //     )).toList();
  //   });
  // } catch (e) {
  //   print('Error fetching and showing grid information: $e');
  // }
}



  void resetGame() {
    setState(() {
      squares = List.filled(16, '');
      currentPlayer = 'X';
    });
  }

  void makeMove(int index) {
    int row = index ~/ 4;
    int col = index % 4;

    // Sadece son satır ve son sütun harici hücrelere izin ver
    if (squares[index] == '' && row != 0 && col != 0) {
      setState(() {
        squares[index] = currentPlayer;
        currentPlayer = (currentPlayer == 'X') ? 'O' : 'X';

        // Kazanan kontrolü burada yapılıyor
        if (checkWin('X')) {
          showDialog(
            context: context,
            builder: (_) => gameOverDialog('X'),
          );
        } else if (checkWin('O')) {
          showDialog(
            context: context,
            builder: (_) => gameOverDialog('O'),
          );
        } else if (isBoardFull()) {
          showDialog(
            context: context,
            builder: (_) => gameOverDialog('T'),
          );
        }
      });
    }
  }

  bool checkWin(String player) {
    // Kazanma kontrolleri burada yapılıyor
    // ...

    return false;
  }

  bool isBoardFull() {
    return !squares.contains('');
  }

  @override
  Widget build(BuildContext context) {
    Size screenSize = MediaQuery.of(context).size;
    double boxSize = screenSize.width / 4 * 0.8;

    return Scaffold(
      appBar: null,
      body: Stack(
        alignment: Alignment.center,
        children: [
          BackgroundWidget(),
          Positioned(
            top: screenSize.height / 13 + boxSize * 2,
            left: screenSize.width / 9,
            right: screenSize.width / 9,
            child: SizedBox(
              width: boxSize * 4,
              height: boxSize * 4,
              child: GridView.builder(
                padding: EdgeInsets.all(0),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 0,
                  crossAxisSpacing: 0,
                ),
                itemBuilder: (context, index) {
                  return GestureDetector(
                    
                    onTap: () {
                      if (!checkWin('X') && !checkWin('O') && !isBoardFull()) {
                        makeMove(index);
                        if (checkWin('X')) {
                          showDialog(
                            context: context,
                            builder: (_) => gameOverDialog('X'),
                          );
                        } else if (checkWin('O')) {
                          showDialog(
                            context: context,
                            builder: (_) => gameOverDialog('O'),
                          );
                        } else if (isBoardFull()) {
                          showDialog(
                            context: context,
                            builder: (_) => gameOverDialog('T'),
                          );
                        }
                      }
                    },
                    child: SizedBox(
                      width: boxSize,
                      height: boxSize,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white),
                        ),
                        child: Center(
                          child: Text(
                            squares[index],
                            style: TextStyle(fontSize: 30),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                itemCount: 16,
              ),
            ),
          ),
          Positioned(
            left: screenSize.width * 0.55,
            bottom: screenSize.height * 0.05,
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => StartPage()),
                );
              },
              child: Image.asset(
                'images/leave.png',
                width: screenSize.width * 0.4,
                height: screenSize.height * 0.2,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Positioned(
            right: screenSize.width * 0.55,
            bottom: screenSize.height * 0.05,
            child: GestureDetector(
              onTap: () async {

                // var object= new ApiService("http://localhost:8000");
                // var value=await object.getFinalGrid("TR1");

                print("RESULT IS ");



                resetGame();
                
              },
              child: Image.asset(
                'images/replay.png',
                width: screenSize.width * 0.4,
                height: screenSize.height * 0.2,
                fit: BoxFit.contain,
              ),
            ),
          ),
          
        ],
      ),
    );
  }

  Widget gameOverDialog(String winner) {
    String message;
    if (winner == 'T') {
      message = 'Oyun berabere!';
    } else {
      message = 'Kazanan: $winner';
    }

    return AlertDialog(
      title: Text('Oyun Bitti'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () {
            resetGame();
            
            Navigator.of(context).pop();
          },
          child: Text('Yeniden Başla'),
        ),
      ],
    );
  }
}
