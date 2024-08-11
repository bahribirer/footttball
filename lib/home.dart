import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:footttball/Services/api_service.dart';
import 'package:footttball/Helper/helper.dart';
import 'package:footttball/Models/teamModel.dart';
import 'package:footttball/Services/websocket.dart';
import 'package:footttball/getInfo.dart';
import 'package:footttball/main.dart';
import 'package:footttball/Models/players.dart';
import 'package:footttball/Rooms/startPage.dart';

class TikiTakaToeGame extends StatefulWidget {
  final TeamModel teammodel;
  final String gamemode;
  final String player1Name;
  final String player2Name;

  TikiTakaToeGame(
      {Key? key,
      required this.teammodel,
      required this.gamemode,
      required this.player1Name,
      required this.player2Name})
      : super(key: key);

  @override
  _TikiTakaToeGameState createState() => _TikiTakaToeGameState();
}

class _TikiTakaToeGameState extends State<TikiTakaToeGame> {
  late List<Player> players;
  late String currentPlayer;
  late List<String> squares;
  List<String> urls = [];
  int teamindex = -1;
  int countryindex = -1;
  var teamobject = getTeamInfo();

  late Timer _timer;
  int _start = 30;

  String player1Name = '';
  String player2Name = '';

  @override
  void initState() {
    super.initState();
    WebSocketManager().makeMove = makeMove;
    getLogoUrl();
    resetGame();
    startTimer();

    player1Name = widget.player1Name;
    player2Name = widget.player2Name;
  }

  void startTimer() {
    const oneSec = Duration(seconds: 1);
    _timer = Timer.periodic(
      oneSec,
      (Timer timer) {
        if (_start == 0) {
          setState(() {
            timer.cancel();
            _start = 30;
            startTimer();
            WebSocketManager().playerTurn = !WebSocketManager().playerTurn;
          });
        } else {
          setState(() {
            _start--;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void getLogoUrl() async {
    for (int i = 0; i < 3; i++) {
      var value = await ApiService.getLogo(
          gamemode: widget.gamemode, countryname: widget.teammodel.clubs[i]);
      urls.add(value);
    }
    setState(() {});
  }

  int controlTeamIndex() {
    if (teamindex >= 2) {
      teamindex = 0;
    } else {
      teamindex++;
    }
    return teamindex;
  }

  int controlCountryIndex() {
    if (teamindex >= 2) {
      teamindex = 0;
    } else {
      teamindex++;
    }
    return teamindex;
  }

  void resetTimer() {
    _timer.cancel();
    _start = 30;
    startTimer();
  }

  void resetGame() {
    setState(() {
      squares = List.filled(16, '');
      currentPlayer = WebSocketManager().initialType;
    });
    squares[1] = "image";
    squares[2] = "image";
    squares[3] = "image";
  }

  void makeMove(int index, String type) {
    int row = index ~/ 4;
    int col = index % 4;

    if (index != -1 && squares[index] == '' && row != 0 && col != 0) {
      squares[index] = type;
    }
    var player1 = checkWin("X");
    var player2 = checkWin("O");

    if (player1 || player2) {
      setState(() {
        WebSocketManager().playerTurn = true;
        resetTimer();
      });
    }

    showStatus(player1, "X");
    showStatus(player2, "O");

    if (!player1 && !player2) {
      setState(() {
        WebSocketManager().playerTurn = !WebSocketManager().playerTurn;
        resetTimer();
      });
    }
  }

  bool checkWin(String player) {
    bool horizontalWin = (squares[5] == player &&
            squares[6] == player &&
            squares[7] == player) ||
        (squares[9] == player &&
            squares[10] == player &&
            squares[11] == player) ||
        (squares[13] == player &&
            squares[14] == player &&
            squares[15] == player);

    bool verticalWin = (squares[5] == player &&
            squares[9] == player &&
            squares[13] == player) ||
        (squares[6] == player &&
            squares[10] == player &&
            squares[14] == player) ||
        (squares[7] == player &&
            squares[11] == player &&
            squares[15] == player);

    bool diagonalWin = (squares[5] == player &&
            squares[10] == player &&
            squares[15] == player) ||
        (squares[7] == player &&
            squares[10] == player &&
            squares[13] == player);

    return horizontalWin || verticalWin || diagonalWin;
  }

  bool isBoardFull() {
    return !squares.contains('');
  }

  void showStatus(bool player1, String value) {
    if (player1) {
      Helper().showInfoDialog(context, "WIN!", "$value WON THE GAME ");
    }
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
                  return IgnorePointer(
                    ignoring: !WebSocketManager().playerTurn,
                    child: GestureDetector(
                      onTap: () async {
                        if (squares[index] == "") {
                          var result = await Helper().showPlayerName(
                              context,
                              widget.teammodel.clubs[(index % 4) - 1],
                              widget.teammodel.nations[(index ~/ 4) - 1]);
                          if (result) {
                            WebSocketManager().send(jsonEncode(
                                {"index": index, "type": currentPlayer}));
                          } else {
                            WebSocketManager().send(jsonEncode(
                                {"index": -1, "type": currentPlayer}));
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
                              child: (index == 1 || index == 2 || index == 3)
                                  ? urls.isEmpty
                                      ? CircularProgressIndicator()
                                      : Image.network(urls[controlTeamIndex()])
                                  : (index == 4 || index == 8 || index == 12)
                                      ? Image.network("https://flagsapi.com/" +
                                          teamobject.getCountry(widget.teammodel
                                              .nations[controlCountryIndex()]) +
                                          "/flat/64.png")
                                      : Text(
                                          squares[index],
                                          style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold),
                                        )),
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
            left: MediaQuery.of(context).size.width * 0.10,
            bottom: MediaQuery.of(context).size.height * 0.70,
            child: Column(
              children: [
                Text(
                  "TURN",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: MediaQuery.of(context).size.width * 0.05,
                  ),
                ),
                Container(
                  width: 35.0,
                  height: 35.0,
                  decoration: BoxDecoration(
                    color: WebSocketManager().playerTurn
                        ? Colors.green
                        : Colors.red,
                    shape: BoxShape.circle,
                  ),
                )
              ],
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
          Positioned(
            top: MediaQuery.of(context).size.height * 0.20,
            child: Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$_start',
                style: TextStyle(fontSize: 36, color: Colors.white),
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
