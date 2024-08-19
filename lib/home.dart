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

class _TikiTakaToeGameState extends State<TikiTakaToeGame>
    with SingleTickerProviderStateMixin {
  late List<Player> players;
  late String currentPlayer;
  late List<String> squares;
  List<String> urls = [];
  int teamindex = -1;
  int countryindex = -1;
  var teamobject = getTeamInfo();

  late Timer _timer;
  int _start = 30;
  bool isInputActive = false;

  late AnimationController _animationController;

  String player1Name = '';
  String player2Name = '';

  @override
  void initState() {
    super.initState();
    WebSocketManager().makeMove = makeMove;
    WebSocketManager().onPlayerLeave = handlePlayerLeave;
    getLogoUrl();
    resetGame();
    startTimer();

    player1Name = widget.player1Name;
    player2Name = widget.player2Name;

    _animationController =
        AnimationController(vsync: this, duration: Duration(seconds: 1))
          ..repeat(reverse: true);
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
            WebSocketManager().playerTurn = !WebSocketManager().playerTurn;
            isInputActive = false; // Close the input box if time runs out
            startTimer();
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
    _animationController.dispose();
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
        isInputActive = false;
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

  void handlePlayerLeave() {
    Helper().showInfoDialog(
        context, "User Left", "The other player has left the room.");
    WebSocketManager().close();
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => StartPage()),
        (route) => false,
      );
    });
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
          // Centered Grid
          Positioned(
            top: screenSize.height * 0.25,
            left: screenSize.width * 0.05,
            right: screenSize.width * 0.05,
            child: SizedBox(
              width: screenSize.width * 0.9,
              height: screenSize.width * 0.9, // Maintain square grid
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
                          setState(() {
                            isInputActive = true;
                          });
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
                          setState(() {
                            isInputActive = false;
                          });
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
          // Turn indicator with animation
          Positioned(
            left: screenSize.width * 0.05,
            top: screenSize.height * 0.15,
            child: Column(
              children: [
                Text(
                  "TURN",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: screenSize.width * 0.05,
                  ),
                ),
                ScaleTransition(
                  scale:
                      Tween(begin: 1.0, end: 1.5).animate(_animationController),
                  child: Icon(
                    WebSocketManager().playerTurn ? Icons.person : Icons.group,
                    color: WebSocketManager().playerTurn
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    size: screenSize.width * 0.1,
                  ),
                ),
              ],
            ),
          ),
          // Timer in the top-right corner
          Positioned(
            top: screenSize.height * 0.10,
            right: screenSize.width * 0.05,
            child: Container(
              width: screenSize.width * 0.15,
              height: screenSize.width * 0.15,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: _start / 30,
                    valueColor: AlwaysStoppedAnimation(Colors.blueAccent),
                    backgroundColor: Colors.grey.shade200,
                    strokeWidth: 5.0,
                  ),
                  Center(
                    child: Text(
                      '$_start',
                      style: TextStyle(
                          fontSize: 20.0, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Leave Room Button
          Positioned(
            left: screenSize.width * 0.55,
            bottom: screenSize.height * 0.05,
            child: GestureDetector(
              onTap: () {
                WebSocketManager().close();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => StartPage()),
                  (route) => false,
                );
              },
              child: Image.asset(
                'images/leave.png',
                width: screenSize.width * 0.3,
                height: screenSize.height * 0.1,
                fit: BoxFit.contain,
              ),
            ),
          ),
          // Replay Button
          Positioned(
            right: screenSize.width * 0.55,
            bottom: screenSize.height * 0.05,
            child: GestureDetector(
              onTap: () async {
                WebSocketManager().send("replayRequest");
              },
              child: Image.asset(
                'images/replay.png',
                width: screenSize.width * 0.3,
                height: screenSize.height * 0.1,
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
