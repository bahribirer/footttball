import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:footttball/Services/api_service.dart';
import 'package:footttball/Helper/helper.dart';
import 'package:footttball/Models/teamModel.dart';
import 'package:footttball/Services/websocket.dart';
import 'package:footttball/getInfo.dart';
import 'package:footttball/main.dart';
import 'package:footttball/Models/players.dart';
import 'package:footttball/Rooms/startPage.dart';
import 'package:footttball/Helper/globals.dart' as globals;
import 'package:footttball/UI/replay_request_dialog.dart';

class TikiTakaToeGame extends StatefulWidget {
  final TeamModel teammodel;
  final String gamemode;
  final String player1Name;
  final String player2Name;
  final int roundCount;

  TikiTakaToeGame(
      {Key? key,
      required this.teammodel,
      required this.gamemode,
      required this.player1Name,
      required this.player2Name,
      this.roundCount = 1})
      : super(key: key);

  @override
  _TikiTakaToeGameState createState() => _TikiTakaToeGameState();
}

class _TikiTakaToeGameState extends State<TikiTakaToeGame>
    with SingleTickerProviderStateMixin {
  late List<Player> players;
  late String currentPlayer;
  late List<String> squares;
  List<String> squareNames = []; // Stores the player name for each cell
  List<String> urls = [];
  int teamindex = -1;
  int countryindex = -1;
  var teamobject = getTeamInfo();

  Timer _timer = Timer(Duration.zero, () {});
  int _start = 30;
  bool isInputActive = false;
  bool _replayRequestSent = false;

  late AnimationController _animationController;

  late String myName;
  String opponentName = "...";
  
  // Scoreboard Variables
  int myScore = 0;
  int opponentScore = 0;
  int currentRound = 1;
  bool _currentRoundWasDraw = false;
  int myStealRights = 3; // Total steal rights for the match
  int opponentStealRights = 3;
  int opponentSelectionIndex = -1; // -1 means no selection

  @override
  void initState() {
    super.initState();
    print("DEBUG: TikiTakaToeGame started with gamemode: ${widget.gamemode}");
    // My name is always the name I entered locally
    myName = globals.player1Name.isNotEmpty ? globals.player1Name : "Player";
    
    // If the creator's name was passed and I'm NOT the creator, use it as opponent
    if (widget.player1Name.isNotEmpty && WebSocketManager().initialType == "O") {
      opponentName = widget.player1Name;
    }

    print("My Name: $myName (${WebSocketManager().initialType})");
    print("Opponent Name: $opponentName");
    
    // Announce my name to the opponent
    Future.delayed(Duration(milliseconds: 500), () {
      WebSocketManager().send(jsonEncode({
        "type": "announceName",
        "name": globals.player1Name,
        "playerType": WebSocketManager().initialType
      }));
    });

    super.initState();
    WebSocketManager().makeMove = makeMove;
    WebSocketManager().onPlayerLeave = handlePlayerLeave;
    WebSocketManager().onReplayRequest = _showReplayDialog;
    WebSocketManager().onReplayDataReceived = _handleReplayDataReceived;
    WebSocketManager().onReplayDeclined = () {
      setState(() { _replayRequestSent = false; });
    };
    
    // Listen for name announcements — only update opponent's name
    WebSocketManager().onNameAnnounced = (name, type) {
      // If the announced type is different from mine, it's the opponent
      if (type != WebSocketManager().initialType) {
        setState(() {
          opponentName = name;
        });
        print("Opponent name updated: $opponentName");
      }
    };

    // Listen for timer sync from the active player — DISPLAY ONLY, no turn logic
    WebSocketManager().onTimerSync = (seconds) {
      // Only apply if it's NOT my turn (I'm the passive/waiting player)
      if (!WebSocketManager().playerTurn) {
        setState(() {
          _start = seconds;
        });
      }
    };

    WebSocketManager().onCellSelected = (index) {
      if (mounted) {
        setState(() {
          opponentSelectionIndex = index;
        });
      }
    };
    
    WebSocketManager().onNextRoundRequest = _handleNextRoundRequest;
    WebSocketManager().onNextRoundData = _handleNextRoundData;

    getLogoUrl();
    resetGame();
    startTimer();

    _animationController =
        AnimationController(vsync: this, duration: Duration(seconds: 1))
          ..repeat(reverse: true);
  }

  void startTimer() {
    _timer.cancel();
    _start = 30;
    const oneSec = Duration(seconds: 1);
    _timer = Timer.periodic(
      oneSec,
      (Timer timer) {
        // Only the active player runs the timer
        if (!WebSocketManager().playerTurn) {
          timer.cancel();
          return;
        }
        if (_start <= 1) {
          // Time's up!
          timer.cancel();
          
          // Force close dialog if open
          if (isInputActive && mounted) {
             Navigator.of(context).pop(); 
          }

          setState(() {
            _start = 0;
            isInputActive = false;
          });
          // Send timeout as a regular move (index: -1) — this gets broadcast to both
          WebSocketManager().send(jsonEncode(
              {"index": -1, "type": WebSocketManager().initialType}));
        } else {
          setState(() {
            _start--;
          });
          // Broadcast timer value to opponent for display sync
          _broadcastTimer(_start);
        }
      },
    );
  }

  void _broadcastTimer(int seconds) {
    WebSocketManager().send(jsonEncode({
      "type": "timerSync",
      "seconds": seconds,
    }));
  }

  void _showReplayDialog() {
    if (!WebSocketManager().playerTurn) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return ReplayRequestDialog(
            onAccept: () async {
              Navigator.of(context).pop();
              // Fetch new data and broadcast it to the room
              _fetchAndBroadcastReplayData();
            },
            onDecline: () {
              Navigator.of(context).pop();
              WebSocketManager().send("replayDecline");
            },
          );
        },
      );
    }
  }

  void _handleReplayDataReceived() {
    // Data is already updated in WebSocketManager's teammodel, which matches widget.teammodel
    setState(() {
      _replayRequestSent = false;
      // Reset Steal Rights for new match
      myStealRights = 3;
      opponentStealRights = 3;
      resetGame();
      currentPlayer = WebSocketManager().initialType;
      getLogoUrl(); // Refresh logos for new teams
    });
    startTimer(); // Restart timer for the new round
  }

  void _fetchAndBroadcastReplayData() async {
    print("DEBUG: _fetchAndBroadcastReplayData called with gamemode: ${widget.gamemode}");
    try {
      // Fetch new data
      var replayData = await ApiService.fetchReplayData(widget.gamemode);

      // Send to opponent (and back to self via broadcast)
      // We construct the message manually to match what websocket.dart expects
      WebSocketManager().send(jsonEncode({
        "type": "replayData",
        "nations": replayData['nations'],
        "clubs": replayData['clubs']
      }));
      
      // Note: We don't need to manually update state here because 
      // the backend will broadcast this message back to us, 
      // triggering _handleReplayDataReceived via WebSocketManager.
    } catch (e) {
      print("Error fetching/broadcasting replay data: $e");
    }
  }



  @override
  void dispose() {
    _timer.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void getLogoUrl() async {
    urls.clear();
    if (widget.teammodel.clubs.length < 3) return; // Not enough data yet
    for (int i = 0; i < 3; i++) {
      var value = await ApiService.getLogo(
          gamemode: widget.gamemode, countryname: widget.teammodel.clubs[i]);
      urls.add(value);
    }
    if (mounted) setState(() {});
  }

  int controlTeamIndex() {
    if (countryindex >= 2) {
      countryindex = 0;
    } else {
      countryindex++;
    }
    return countryindex;
  }

  int controlCountryIndex() {
    int teamindex = (controlTeamIndex());
    if (teamindex >= 2) {
      teamindex = 0;
    } else {
      teamindex++;
    }
    return teamindex;
  }

  void resetTimer() {
    _timer.cancel();
    startTimer();
  }

  void resetGame() {
    setState(() {
      squares = List.filled(16, '');
      squareNames = List.filled(16, ''); // Initialize names
      currentPlayer = WebSocketManager().initialType;
    });
    squares[1] = "image";
    squares[2] = "image";
    squares[3] = "image";
  }

  void makeMove(int index, String type, String? playerName) {
    // ===== SINGLE SOURCE OF TRUTH FOR TURNS =====
    // This function is called on BOTH devices from WebSocket broadcast.
    // It is the ONLY place that changes playerTurn.

    int row = index ~/ 4;
    int col = index % 4;

    // Steal Logic Detection
    bool isSteal = false;
    String? victimType;
    if (index != -1 && index < 16 && squares[index] != '' && squares[index] != type) {
      isSteal = true;
      victimType = squares[index];
    }

    // Allow move if empty OR if it's a valid steal
    if (index != -1 && index < 16 && (squares[index] == '' || isSteal) && row != 0 && col != 0) {
      squares[index] = type;
      if (playerName != null) {
        squareNames[index] = playerName;
      }
      
      // Handle Steal Consequences
      if (isSteal) {
         if (type == WebSocketManager().initialType) {
            // I stole
            myStealRights--; 
         } else {
            // Opponent stole
            opponentStealRights--;
            // If I was the victim, show animation
            if (victimType == WebSocketManager().initialType) {
               _showStealedAnimation();
            }
         }
      }
    }
    var player1 = checkWin("X");
    var player2 = checkWin("O");

    if (player1 || player2) {
      // Game won — cancel timer, DON'T change turns
      setState(() {
        _timer.cancel();
      });
    }

    showStatus(player1, "X");
    showStatus(player2, "O");

    if (!player1 && !player2) {
      // Check for Draw
      if (isBoardFull()) {
        _timer.cancel();
        isRoundOverDialogOpen = true;
        _currentRoundWasDraw = true;
        _suppressNextRoundTrigger = false;
        Helper().showInfoDialog(context, "BERABERE", "Oyun berabere bitti!", onDismiss: () {
          isRoundOverDialogOpen = false;
          if (_suppressNextRoundTrigger) {
            _suppressNextRoundTrigger = false;
            return;
          }
          _onNextRoundClicked();
        });
        return;
      }
      // No win — switch turns
      
      // Safety: If turn switches from external source and dialog is open
      if (isInputActive && mounted) {
         Navigator.of(context).pop();
      }

      setState(() {
        WebSocketManager().playerTurn = !WebSocketManager().playerTurn;
        isInputActive = false;
        resetTimer(); // New active player starts their timer
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
    const playableIndices = [5, 6, 7, 9, 10, 11, 13, 14, 15];
    return playableIndices.every((index) => squares[index] != '');
  }

  bool isRoundOverDialogOpen = false;
  bool _isFetching = false;
  int _lastFetchedRound = 0;
  bool _suppressNextRoundTrigger = false; // Flag to prevent auto-fetch loop

  void _onNextRoundClicked() {
    if (WebSocketManager().initialType == "X") {
      // P1 Logic: Fetch if not already done for this round
      int targetRound = _currentRoundWasDraw ? currentRound : currentRound + 1;
      if (!_isFetching && _lastFetchedRound < targetRound) {
         _fetchAndBroadcastNextRound();
      }
    } else {
       // P2 Logic: Request
       WebSocketManager().send(jsonEncode({
         "type": "requestNextRound", 
         "fromRound": currentRound 
       }));
    }
  }

  void _handleNextRoundRequest() {
    if (WebSocketManager().initialType == "X") {
      // Check if we already fetched for the upcoming round
      int targetRound = _currentRoundWasDraw ? currentRound : currentRound + 1;
      if (!_isFetching && _lastFetchedRound < targetRound) {
        _fetchAndBroadcastNextRound();
      }
    }
  }

  void _fetchAndBroadcastNextRound() async {
    setState(() {
      _isFetching = true;
    });

    try {
      int targetRound = _currentRoundWasDraw ? currentRound : currentRound + 1;
      print("DEBUG: _fetchAndBroadcastNextRound called with gamemode: ${widget.gamemode}");
      var nextRoundData = await ApiService.fetchReplayData(widget.gamemode);
      
      _lastFetchedRound = targetRound; // Mark as fetched
      
      WebSocketManager().send(jsonEncode({
        "type": "nextRoundData",
        "round": targetRound, // Source of Truth
        "nations": nextRoundData['nations'],
        "clubs": nextRoundData['clubs']
      }));
    } catch (e) {
      print("Error fetching next round data: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isFetching = false;
        });
      }
    }
  }

  void _handleNextRoundData(Map<String, dynamic> decoded) {
    int incomingRound = decoded["round"] ?? (currentRound + 1);

    // 1. Close dialog if open (i.e. if I didn't click it yet)
    if (isRoundOverDialogOpen && mounted) {
      _suppressNextRoundTrigger = true; // Prevent onDismiss from triggering fetch
      Navigator.of(context).pop();
      isRoundOverDialogOpen = false;
    }
    
    // 2. Update Data
    widget.teammodel.nations = List<String>.from(decoded["nations"]);
    widget.teammodel.clubs = List<String>.from(decoded["clubs"]);

    // 3. Reset Game State with Explicit Round
    setState(() {
       currentRound = incomingRound; // Set explicit value
       _currentRoundWasDraw = false; // Reset draw flag
       resetGame();
       getLogoUrl(); // Refresh logos
    });
    startTimer();
  }

  void showStatus(bool hasWon, String winnerType) {
    if (hasWon) {
      // Did I win or did opponent win?
      bool iWon = (winnerType == WebSocketManager().initialType);
      if (iWon) {
        myScore++;
      } else {
        opponentScore++;
      }

      String roundWinnerName = iWon ? myName : opponentName;
      _currentRoundWasDraw = false;

      // Check for Series Win (First to X)
      bool seriesOver = false;
      
      // If roundCount is 1, it's a single game.
      // If roundCount > 1, it implies "First to X wins"
      if (myScore >= widget.roundCount || opponentScore >= widget.roundCount) {
        seriesOver = true;
      }

      if (seriesOver) {
         String seriesWinner = myScore > opponentScore ? myName : (opponentScore > myScore ? opponentName : "Draw");
         Helper().showInfoDialog(context, "SERIES OVER", "$seriesWinner wins the series $myScore - $opponentScore!", onDismiss: () {
             Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => StartPage()));
         });
      } else {
         isRoundOverDialogOpen = true;
         _suppressNextRoundTrigger = false; // Reset flag when opening
         Helper().showInfoDialog(context, "ROUND OVER", "$roundWinnerName wins this round!", onDismiss: () {
             isRoundOverDialogOpen = false;
             
             // Check if we should suppress the trigger (because we closed programmatically)
             if (_suppressNextRoundTrigger) {
               _suppressNextRoundTrigger = false;
               return;
             }
             
             _onNextRoundClicked();
         });
      }
    }
  }

  void handlePlayerLeave() {
    // Strict disconnection policy: Show Dialog and Redirect
    if (mounted) {
      _timer.cancel();
      showGeneralDialog(
        barrierDismissible: false,
        barrierLabel: '',
        barrierColor: Colors.black54,
        transitionDuration: Duration(milliseconds: 400),
        pageBuilder: (ctx, anim1, anim2) => Center(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 30),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.redAccent.withOpacity(0.4),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withOpacity(0.3),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 28),
                  Text("💔", style: TextStyle(fontSize: 52)),
                  SizedBox(height: 12),
                  Text(
                    "DISCONNECTED",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      shadows: [
                        Shadow(
                          blurRadius: 12,
                          color: Colors.redAccent.withOpacity(0.6),
                          offset: Offset(0, 0),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 14),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      "Your opponent has left the game.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  SizedBox(height: 26),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: GestureDetector(
                      onTap: () {
                        WebSocketManager().close();
                        Navigator.pushAndRemoveUntil(
                          ctx,
                          MaterialPageRoute(builder: (context) => StartPage()),
                          (route) => false,
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.amberAccent, Colors.orangeAccent],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.amber.withOpacity(0.4),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            "🏠  RETURN TO MENU",
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
        transitionBuilder: (ctx, anim1, anim2, child) => BackdropFilter(
          filter: ImageFilter.blur(
              sigmaX: 6 * anim1.value, sigmaY: 6 * anim1.value),
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            child: FadeTransition(
              opacity: anim1,
              child: child,
            ),
          ),
        ),
        context: context,
      );
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
                          bool isOpponentCell = (squares[index] != "" && squares[index] != currentPlayer);
                          bool canSteal = isOpponentCell && myStealRights > 0;

                          if ((squares[index] == "" || canSteal) &&
                              WebSocketManager().playerTurn) {
                            setState(() {
                              isInputActive = true;
                            });

                            // Broadcast selection to opponent
                            WebSocketManager().send(jsonEncode(
                                {"type": "selectCell", "index": index}));

                            var result = await Helper().showPlayerName(
                                context,
                                widget.teammodel.clubs[(index % 4) - 1],
                                widget.teammodel.nations[(index ~/ 4) - 1]);

                            // Broadcast deselect
                            WebSocketManager().send(jsonEncode(
                                {"type": "deselectCell"}));

                            if (result == true) {
                              // Correct guess — send the move
                              WebSocketManager().send(jsonEncode(
                                  {
                                    "index": index,
                                    "type": currentPlayer,
                                    "playerName": Helper().playerName.text // Send the guessed name
                                  }));
                            } else if (result == false) {
                              // Wrong guess — send turn switch
                              WebSocketManager().send(jsonEncode(
                                  {"index": -1, "type": currentPlayer}));
                            }
                            // result == null means cancel — do nothing, keep turn

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
                              border: Border.all(
                                color: (index == opponentSelectionIndex) 
                                    ? Colors.purpleAccent 
                                    : Colors.white,
                                width: (index == opponentSelectionIndex) ? 3 : 1,
                              ),
                              boxShadow: (index == opponentSelectionIndex)
                                  ? [
                                      BoxShadow(
                                        color: Colors.purpleAccent.withOpacity(0.6),
                                        blurRadius: 15,
                                        spreadRadius: 2,
                                      )
                                    ]
                                  : [],
                            ),
                            child: Center(
                              child: (index == 1 || index == 2 || index == 3)
                                  ? urls.length < 3
                                      ? CircularProgressIndicator()
                                      : Image.network(
                                          urls[(index % 4) - 1],
                                          headers: const {
                                            "User-Agent": "TikiTaka/1.0"
                                          },
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                            final clubIdx = (index % 4) - 1;
                                            return _buildFallbackShield(
                                                clubIdx <
                                                        widget.teammodel.clubs
                                                            .length
                                                    ? widget.teammodel
                                                        .clubs[clubIdx]
                                                    : '?');
                                          },
                                        )
                                  : (index == 4 || index == 8 || index == 12)
                                      ? widget.teammodel.nations.length >= 3
                                          ? Image.network(
                                              teamobject.getCountry(widget
                                                          .teammodel.nations[
                                                      (index ~/ 4) - 1]) ==
                                                      "XK"
                                                  ? "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1f/Flag_of_Kosovo.svg/120px-Flag_of_Kosovo.svg.png"
                                                  : "https://flagsapi.com/" +
                                                      teamobject.getCountry(widget
                                                          .teammodel.nations[
                                                      (index ~/ 4) - 1]) +
                                                      "/flat/64.png",
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                return Icon(Icons.flag,
                                                    color: Colors.white,
                                                    size: 40);
                                              },
                                            )
                                          : CircularProgressIndicator()
                                      : index == 0
                                          ? SizedBox.expand(
                                              child: Image.asset(
                                                "images/app_logo.png",
                                                fit: BoxFit.cover,
                                              ),
                                            )
                                          : squares[index] == "X"
                                              ? Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.withOpacity(0.15),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Stack(
                                                    alignment: Alignment.center,
                                                    children: [
                                                      Center(
                                                        child: Text(
                                                          "X",
                                                          style: TextStyle(
                                                            fontSize: 55,
                                                            fontWeight: FontWeight.w900,
                                                            color: Colors.greenAccent,
                                                            shadows: [
                                                              Shadow(
                                                                blurRadius: 12,
                                                                color: Colors.greenAccent.withOpacity(0.8),
                                                                offset: Offset(0, 0),
                                                              ),
                                                              Shadow(
                                                                blurRadius: 24,
                                                                color: Colors.green.withOpacity(0.4),
                                                                offset: Offset(0, 0),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                      if (squareNames.length > index && squareNames[index].isNotEmpty)
                                                        Positioned(
                                                          bottom: 0,
                                                          left: 0,
                                                          right: 0,
                                                          height: 28,
                                                          child: Container(
                                                            decoration: BoxDecoration(
                                                              gradient: LinearGradient(
                                                                begin: Alignment.bottomCenter,
                                                                end: Alignment.topCenter,
                                                                colors: [
                                                                  Colors.black.withOpacity(0.9),
                                                                  Colors.transparent,
                                                                ],
                                                              ),
                                                              borderRadius: BorderRadius.only(
                                                                  bottomLeft: Radius.circular(8),
                                                                  bottomRight: Radius.circular(8)),
                                                            ),
                                                            alignment: Alignment.bottomCenter,
                                                            padding: EdgeInsets.only(bottom: 4),
                                                            child: Text(
                                                              squareNames[index],
                                                              textAlign: TextAlign.center,
                                                              style: TextStyle(
                                                                  color: Colors.white,
                                                                  fontSize: 10,
                                                                  fontWeight: FontWeight.bold,
                                                                  shadows: [
                                                                    Shadow(
                                                                        blurRadius: 2,
                                                                        color: Colors.black,
                                                                        offset: Offset(0, 1))
                                                                  ]),
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        )
                                                    ],
                                                  ),
                                                )
                                          : squares[index] == "O"
                                              ? Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.red.withOpacity(0.15),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Stack(
                                                    alignment: Alignment.center,
                                                    children: [
                                                      Center(
                                                        child: Text(
                                                          "O",
                                                          style: TextStyle(
                                                            fontSize: 55,
                                                            fontWeight: FontWeight.w900,
                                                            color: Colors.redAccent,
                                                            shadows: [
                                                              Shadow(
                                                                blurRadius: 12,
                                                                color: Colors.redAccent.withOpacity(0.8),
                                                                offset: Offset(0, 0),
                                                              ),
                                                              Shadow(
                                                                blurRadius: 24,
                                                                color: Colors.red.withOpacity(0.4),
                                                                offset: Offset(0, 0),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                      if (squareNames.length > index && squareNames[index].isNotEmpty)
                                                        Positioned(
                                                          bottom: 0,
                                                          left: 0,
                                                          right: 0,
                                                          height: 28,
                                                          child: Container(
                                                            decoration: BoxDecoration(
                                                              gradient: LinearGradient(
                                                                begin: Alignment.bottomCenter,
                                                                end: Alignment.topCenter,
                                                                colors: [
                                                                  Colors.black.withOpacity(0.9),
                                                                  Colors.transparent,
                                                                ],
                                                              ),
                                                              borderRadius: BorderRadius.only(
                                                                  bottomLeft: Radius.circular(8),
                                                                  bottomRight: Radius.circular(8)),
                                                            ),
                                                            alignment: Alignment.bottomCenter,
                                                            padding: EdgeInsets.only(bottom: 4),
                                                            child: Text(
                                                              squareNames[index],
                                                              textAlign: TextAlign.center,
                                                              style: TextStyle(
                                                                  color: Colors.white,
                                                                  fontSize: 10,
                                                                  fontWeight: FontWeight.bold,
                                                                  shadows: [
                                                                    Shadow(
                                                                        blurRadius: 2,
                                                                        color: Colors.black,
                                                                        offset: Offset(0, 1))
                                                                  ]),
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        )
                                                    ],
                                                  ),
                                                )
                                              : SizedBox(),
                            ),
                          ),
                        ),
                      ));
                },
                itemCount: 16,
              ),
            ),
          ),
          // Turn indicator with animation
          // Premium Scoreboard — BELOW the board, above the timer
          Positioned(
            left: 30,
            right: 30,
            bottom: screenSize.height * 0.22,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.deepPurple.withOpacity(0.7),
                    Colors.purple.withOpacity(0.5),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withOpacity(0.4),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // ME (left side - green when my turn)
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.sports_soccer,
                                color: WebSocketManager().playerTurn
                                    ? Colors.greenAccent
                                    : Colors.white60,
                                size: 14),
                            SizedBox(width: 4),
                            Text(
                              myName.length > 7
                                  ? myName.substring(0, 7) + ".."
                                  : myName,
                              style: TextStyle(
                                color: WebSocketManager().playerTurn
                                    ? Colors.greenAccent
                                    : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 2),
                        // Steal Rights (ME)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(3, (i) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 1.0),
                              child: Icon(
                                Icons.sports_soccer,
                                size: 14,
                                color: i < myStealRights 
                                    ? Colors.greenAccent 
                                    : Colors.white12,
                              ),
                            );
                          }),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "$myScore",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 26,
                            shadows: [
                              Shadow(
                                blurRadius: 8.0,
                                color: Colors.white.withOpacity(0.4),
                                offset: Offset(0, 0),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Round Info
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "ROUND",
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Text(
                          (widget.roundCount == 1 && currentRound == 1) 
                              ? "MATCH" 
                              : (currentRound > widget.roundCount ? "EXTRA" : "$currentRound/${widget.roundCount}"),
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // OPPONENT (right side - red when their turn)
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              opponentName.length > 7
                                  ? opponentName.substring(0, 7) + ".."
                                  : opponentName,
                              style: TextStyle(
                                color: !WebSocketManager().playerTurn
                                    ? Colors.redAccent
                                    : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.sports_soccer,
                                color: !WebSocketManager().playerTurn
                                    ? Colors.redAccent
                                    : Colors.white60,
                                size: 14),
                          ],
                        ),
                        SizedBox(height: 2),
                        // Steal Rights (OPPONENT)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(3, (i) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 1.0),
                              child: Icon(
                                Icons.sports_soccer,
                                size: 14,
                                color: i < opponentStealRights 
                                    ? Colors.greenAccent 
                                    : Colors.white12,
                              ),
                            );
                          }),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "$opponentScore",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 26,
                            shadows: [
                              Shadow(
                                blurRadius: 8.0,
                                color: Colors.white.withOpacity(0.4),
                                offset: Offset(0, 0),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Premium Timer — BELOW scoreboard, above replay/leave buttons
          Positioned(
            left: 0,
            right: 0,
            bottom: screenSize.height * 0.13,
            child: Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: _start <= 10
                        ? [Colors.red.shade800, Colors.redAccent]
                        : [Color(0xFF6A11CB), Color(0xFF2575FC)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _start <= 10
                          ? Colors.redAccent.withOpacity(0.6)
                          : Colors.blueAccent.withOpacity(0.5),
                      blurRadius: 15,
                      offset: Offset(0, 5),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withOpacity(0.4),
                    width: 2,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: EdgeInsets.all(4),
                      child: CircularProgressIndicator(
                        value: _start / 30,
                        valueColor: AlwaysStoppedAnimation(Colors.white.withOpacity(0.8)),
                        backgroundColor: Colors.white.withOpacity(0.2),
                        strokeWidth: 3.5,
                      ),
                    ),
                    Center(
                      child: Text(
                        '$_start',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              blurRadius: 5.0,
                              color: Colors.black38,
                              offset: Offset(1, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Leave Room Button
          Positioned(
            left: screenSize.width * 0.55,
            bottom: screenSize.height * 0.05,
            child: GestureDetector(
              onTap: () {
                WebSocketManager()
                    .sendLeaveRoom(); // Diğer oyuncuya da çıkma sinyali gönder
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
          // Replay butonuna basıldığında replay isteği gönderilir
          Positioned(
            right: screenSize.width * 0.55,
            bottom: screenSize.height * 0.05,
            child: GestureDetector(
              onTap: () async {
                if (_replayRequestSent) return; // Already sent, wait for response
                // Check if it's the player's turn before sending the replay request
                if (WebSocketManager().playerTurn) {
                  setState(() { _replayRequestSent = true; });
                  WebSocketManager().sendReplayRequest(); // Send replay request
                } else {
                  // Premium "Not Your Turn" popup
                  showGeneralDialog(
                    barrierDismissible: true,
                    barrierLabel: '',
                    barrierColor: Colors.black54,
                    transitionDuration: Duration(milliseconds: 300),
                    pageBuilder: (ctx, anim1, anim2) => Center(
                      child: Container(
                        margin: EdgeInsets.symmetric(horizontal: 30),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.orangeAccent.withOpacity(0.4),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orangeAccent.withOpacity(0.3),
                              blurRadius: 30,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(height: 24),
                              Text("⏳", style: TextStyle(fontSize: 48)),
                              SizedBox(height: 12),
                              Text(
                                "NOT YOUR TURN",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 10,
                                      color: Colors.orangeAccent.withOpacity(0.5),
                                      offset: Offset(0, 0),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 14),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  "Wait for your opponent's move\nbefore requesting a rematch.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                              SizedBox(height: 22),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 32),
                                child: GestureDetector(
                                  onTap: () => Navigator.of(ctx).pop(),
                                  child: Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.symmetric(vertical: 13),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Colors.amberAccent, Colors.orangeAccent],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.amber.withOpacity(0.4),
                                          blurRadius: 12,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        "GOT IT",
                                        style: TextStyle(
                                          color: Colors.black87,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: 22),
                            ],
                          ),
                        ),
                      ),
                    ),
                    transitionBuilder: (ctx, anim1, anim2, child) => ScaleTransition(
                      scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
                      child: FadeTransition(
                        opacity: anim1,
                        child: child,
                      ),
                    ),
                    context: context,
                  );
                }
              },
              child: Opacity(
                opacity: _replayRequestSent ? 0.4 : 1.0,
                child: Image.asset(
                  'images/replay.png',
                  width: screenSize.width * 0.3,
                  height: screenSize.height * 0.1,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          )
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

  Widget _buildFallbackShield(String clubName) {
    String initials = "";
    if (clubName.isNotEmpty) {
      List<String> words = clubName.split(" ");
      if (words.length > 1) {
        initials = "${words[0][0]}${words[1][0]}".toUpperCase();
      } else {
        initials = words[0].length > 1 
            ? "${words[0][0]}${words[0][1]}".toUpperCase() 
            : words[0].toUpperCase();
      }
    } else {
        initials = "FC";
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade900,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 4,
            offset: Offset(2, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            shadows: [
              Shadow(
                blurRadius: 2.0,
                color: Colors.black,
                offset: Offset(1.0, 1.0),
              ),
            ],
          ),
        ),
      ),
    );
  }


  void _showStealedAnimation() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.3), // Light dim
      transitionDuration: Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: ScaleTransition(
              scale: CurvedAnimation(parent: anim1, curve: Curves.elasticOut),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.5),
                      blurRadius: 30,
                      spreadRadius: 5,
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.gpp_bad_rounded, color: Colors.white, size: 50),
                    SizedBox(height: 10),
                    Text(
                      "YOUR SPOT WAS STOLEN!",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(blurRadius: 5, color: Colors.black45)],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    // Auto dismiss
    Future.delayed(Duration(milliseconds: 1500), () {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    });
  }
}
