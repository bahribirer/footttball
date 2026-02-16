import 'dart:math';
import 'dart:ui';
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

class _CreateRoomPageState extends State<CreateRoomPage> with SingleTickerProviderStateMixin {
  String selectedGameMode = ''; // Seçilen oyun modu
  late String roomCode;
  late bool isLeagueSelected;
  var teamobject = getTeamInfo();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

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

    _pulseController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
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

  void _restartGame() async {
    try {
      // Seçilen oyun modu için yeni takım ve ülke bilgilerini getir
      var replayData =
          await ApiService.fetchReplayData(teamobject.getmap(selectedGameMode));

      // Gelen verileri kontrol edin
      if (replayData.isNotEmpty) {
        // `TeamModel` nesnesi oluşturun veya güncelleyin
        TeamModel updatedTeamModel = TeamModel(
          nations: replayData['nations']!,
          clubs: replayData['clubs']!,
        );

        // Yeni bilgilerle `WaitingRoom` veya ilgili sayfaya yönlendirme yapın
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => WaitingRoom(
              room_id: roomCode,
              teammodel: updatedTeamModel,
              gamemode: teamobject.getmap(selectedGameMode),
            ),
          ),
        );
      } else {
        print("Yeni bilgiler alınamadı.");
      }
    } catch (e) {
      print("Hata oluştu: $e");
    }
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
            top: 50,
            left: 20,
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => StartPage()),
                );
              },
              child: Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.2),
                      Colors.white.withOpacity(0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.5),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          // Main Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 160),
                // Positioned ROOM CODE just above Premier League
                  // Premium "Digit Box" Room Code Display
                  Column(
                    children: [
                      Text(
                        'ROOM CODE',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3.0,
                          shadows: [
                            Shadow(
                              color: Colors.black26,
                              offset: Offset(0, 2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: roomCode.split('').map((digit) {
                          return ScaleTransition(
                            scale: _pulseAnimation,
                            child: Container(
                              margin: EdgeInsets.symmetric(horizontal: 5),
                              width: 50,
                              height: 70,
                              decoration: BoxDecoration(
                                color: Color(0xFF1A1A2E), // Dark game background
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.cyanAccent.withOpacity(0.5),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.cyanAccent.withOpacity(0.3),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                  BoxShadow(
                                    color: Colors.purpleAccent.withOpacity(0.2),
                                    blurRadius: 15,
                                    offset: Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  digit,
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(
                                        color: Colors.cyanAccent,
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
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
                      _showRoundSelectionDialog(context);
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

  void _showRoundSelectionDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          backgroundColor: Colors.transparent,
          child: Container(
            padding: EdgeInsets.all(3), // Gradient Border Width
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              gradient: LinearGradient(
                colors: [Colors.cyanAccent, Colors.purpleAccent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.purpleAccent.withOpacity(0.5),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Container(
              padding: EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: Color(0xFF0F0F1E), // Deep Dark Background
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Premium Header "POP" Design
                  Stack(
                    children: [
                      // Stroke / Outline
                      Text(
                        "SELECT ROUNDS",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22, // Reduced size to fit one line
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0, // Reduced spacing
                          foreground: Paint()
                            ..style = PaintingStyle.stroke
                            ..strokeWidth = 4
                            ..color = Colors.cyanAccent.withOpacity(0.5),
                        ),
                      ),
                      // Gradient Text Fill
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [Colors.white, Colors.cyanAccent],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ).createShader(bounds),
                        child: Text(
                          "SELECT ROUNDS",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22, // Reduced size
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Container(
                    height: 3,
                    width: 50,
                    decoration: BoxDecoration(
                      color: Colors.purpleAccent,
                      borderRadius: BorderRadius.circular(1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.purpleAccent.withOpacity(0.6),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildRoundOption(context, 1),
                      _buildRoundOption(context, 3),
                      _buildRoundOption(context, 5),
                    ],
                  ),
                  SizedBox(height: 30),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      "CANCEL",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }


  Widget _buildRoundOption(BuildContext context, int rounds) {
    List<Color> gradientColors;
    IconData iconData;
    Color shadowColor;

    if (rounds == 1) {
      gradientColors = [Color(0xFF00F260), Color(0xFF0575E6)]; // Green/Blue
      iconData = Icons.flash_on_rounded;
      shadowColor = Color(0xFF00F260);
    } else if (rounds == 3) {
      gradientColors = [Color(0xFF8E2DE2), Color(0xFF4A00E0)]; // Purple/Blue
      iconData = Icons.emoji_events_rounded;
      shadowColor = Color(0xFF8E2DE2);
    } else {
      gradientColors = [Color(0xFFFF512F), Color(0xFFDD2476)]; // Orange/Pink
      iconData = Icons.local_fire_department_rounded;
      shadowColor = Color(0xFFFF512F);
    }

    return GestureDetector(
      onTap: () {
        Navigator.of(context).pop();
        _navigateToWaitingRoom(rounds);
      },
      child: Column(
        children: [
          Container(
            width: 80,
            height: 90,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Glowing Hexagon Background
                ClipPath(
                  clipper: HexagonClipper(),
                  child: Container(
                    width: 80,
                    height: 90,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: gradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: shadowColor.withOpacity(0.6),
                          blurRadius: 15,
                          spreadRadius: 2,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.symmetric(
                          vertical: BorderSide(color: Colors.white.withOpacity(0.3), width: 1),
                        ),
                      ),
                    ),
                  ),
                ),
                // Content
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      iconData,
                      color: Colors.white,
                      size: 24,
                    ),
                    Text(
                      "$rounds",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            color: Colors.black45,
                            offset: Offset(1, 1),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 8),
          Text(
            rounds == 1 ? "QUICK" : (rounds == 3 ? "CLASSIC" : "PRO"),
            style: TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToWaitingRoom(int rounds) {
    print("DEBUG: Navigating to WaitingRoom for code: $roomCode in mode: $selectedGameMode");
    
    // Move immediately to WaitingRoom. 
    // The league info will be fetched inside the waiting room to prevent blocking.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WaitingRoom(
          room_id: roomCode,
          teammodel: null, // Host will fetch this asynchronously inside WaitingRoom
          gamemode: teamobject.getmap(selectedGameMode),
          roundCount: rounds,
        ),
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
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.zero,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F2027), Color(0xFF2C5364)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(height: 30),
            ScaleTransition(
              scale: _animation,
              child: Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.redAccent.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 50,
                  color: Colors.redAccent,
                ),
              ),
            ),
            SizedBox(height: 25),
            Text(
              "CHOOSE MODE",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 2.0,
                shadows: [
                  Shadow(
                    blurRadius: 10,
                    color: Colors.redAccent.withOpacity(0.5),
                    offset: Offset(0, 0),
                  ),
                ],
              ),
            ),
            SizedBox(height: 15),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                "You need to select a league before starting the game.",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.8),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: 30),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
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
                        color: Colors.orange.withOpacity(0.3),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      "OK",
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class HexagonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path
      ..moveTo(size.width * 0.5, 0)
      ..lineTo(size.width, size.height * 0.25)
      ..lineTo(size.width, size.height * 0.75)
      ..lineTo(size.width * 0.5, size.height)
      ..lineTo(0, size.height * 0.75)
      ..lineTo(0, size.height * 0.25)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
