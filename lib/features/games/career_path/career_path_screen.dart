import 'dart:async';

import 'package:flutter/material.dart';

import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/models/room_models.dart';
import 'package:footttball/data/services/country_catalog.dart';
import 'package:footttball/data/services/game_socket.dart';
import 'package:footttball/features/modes/mode_select_screen.dart';
import 'package:footttball/shared/widgets/app_background.dart';
import 'package:footttball/shared/widgets/connection_banner.dart';
import 'package:footttball/shared/widgets/game_dialogs.dart';
import 'package:footttball/shared/widgets/player_avatar.dart';
import 'package:footttball/shared/widgets/player_suggestion_field.dart';

/// Kariyer Yolu.
///
/// Bir futbolcunun kulüp yolu adım adım açılır; kim olduğunu ilk bilen
/// turu alır. Her oyuncunun maç boyunca 3 ipucu hakkı vardır ve ipucu
/// yalnızca kullanana bir sonraki kulübü açar — rakip yalnızca "ipucu
/// kullandı" bilgisini görür.
class CareerPathScreen extends StatefulWidget {
  const CareerPathScreen({super.key});

  @override
  State<CareerPathScreen> createState() => _CareerPathScreenState();
}

class _CareerPathScreenState extends State<CareerPathScreen> {
  static const int _answerSeconds = 60;

  final _socket = GameSocket.instance;
  final _answerController = TextEditingController();
  StreamSubscription<SocketEvent>? _subscription;

  CareerState _state = CareerState.empty;
  String? _flash;
  Color _flashColor = Colors.redAccent;
  Timer? _flashTimer;
  bool _gameOver = false;

  /// Az önce açılan kulübü vurgulamak için.
  int? _justRevealed;
  Timer? _revealTimer;

  @override
  void initState() {
    super.initState();
    _state = CareerState.fromJson(_socket.lastState);
    _subscription = _socket.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _flashTimer?.cancel();
    _revealTimer?.cancel();
    _answerController.dispose();
    super.dispose();
  }

  void _onEvent(SocketEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case 'start':
      case 'state':
        final next = CareerState.fromJson(event.payload);
        // Yeni tur başladıysa vurguyu ve alanı temizle.
        if (next.round != _state.round) {
          _answerController.clear();
          _justRevealed = null;
        }
        setState(() => _state = next);
        break;
      case 'event':
        _onGameEvent(event);
        break;
      case 'over':
        _onGameOver(event);
        break;
      case 'opponent_left':
        if (!_gameOver) {
          _gameOver = true;
          GameDialogs.showDisconnected(context, onExit: _exitToMenu);
        }
        break;
    }
  }

  void _onGameEvent(SocketEvent event) {
    final slot = event.value<int>('slot');
    switch (event.event) {
      case 'correct_answer':
        final answer = event.value<String>('answer') ?? '';
        _showFlash(
          slot == _socket.mySlot
              ? 'Doğru! $answer 🎉'
              : 'Rakibin bildi: $answer',
          slot == _socket.mySlot ? Colors.greenAccent : Colors.orangeAccent,
        );
        _answerController.clear();
        break;
      case 'wrong_answer':
        if (slot == _socket.mySlot) {
          final left = event.value<int>('attempts_left') ?? 0;
          _showFlash('Yanlış — kalan deneme: $left', Colors.redAccent);
          _answerController.clear();
        }
        break;
      case 'club_revealed':
        _highlight(event.value<int>('index'));
        break;
      case 'clue_used':
        _highlight(event.value<int>('index'));
        final left = event.value<int>('clues_left') ?? 0;
        _showFlash('İpucu açıldı — kalan hakkın: $left', Colors.cyanAccent);
        break;
      case 'opponent_clue':
        _showFlash('Rakibin ipucu kullandı', Colors.white70);
        break;
    }
  }

  void _highlight(int? index) {
    if (index == null) return;
    _revealTimer?.cancel();
    setState(() => _justRevealed = index);
    _revealTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _justRevealed = null);
    });
  }

  void _onGameOver(SocketEvent event) {
    if (_gameOver) return;
    _gameOver = true;
    final winner = event.value<int>('winner');
    final iWon = winner == _socket.mySlot;
    GameDialogs.showInfo(
      context,
      title: winner == null ? 'BERABERE' : (iWon ? 'KAZANDIN' : 'KAYBETTİN'),
      message:
          'Maç sonucu  ${_state.scoreOf(_socket.mySlot)} - ${_state.scoreOf(_socket.opponentSlot)}',
      actionLabel: '🏠  MENÜYE DÖN',
      onDismiss: _exitToMenu,
    );
  }

  void _showFlash(String text, Color color) {
    _flashTimer?.cancel();
    setState(() {
      _flash = text;
      _flashColor = color;
    });
    _flashTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _submitGuess(String guess) {
    final answer = guess.trim();
    if (answer.isEmpty) return;
    _socket.action('guess', value: answer);
    _answerController.clear();
  }

  void _useClue() => _socket.action('clue');

  void _exitToMenu() {
    _socket.leave();
    _socket.disconnect();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ModeSelectScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitToMenu();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            GameBackground(accent: GameMode.careerPath.colors.first),
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  _buildScoreboard(),
                  if (_flash != null) _buildFlash(),
                  Expanded(
                      child: SingleChildScrollView(child: _buildPhaseBody())),
                ],
              ),
            ),
            const Align(
                alignment: Alignment.topCenter, child: ConnectionBanner()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white54),
            onPressed: _exitToMenu,
          ),
          Expanded(
            child: Column(
              children: [
                const NeonTitle('KARİYER YOLU', fontSize: 18),
                Text(
                  '${_state.round}. TUR  ·  İLK ${_state.totalRounds}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildScoreboard() {
    final me = _socket.mySlot;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: _ScoreTile(
              name: _socket.myName,
              score: _state.scoreOf(me),
              clues: _state.cluesOf(me),
              accent: Colors.cyanAccent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ScoreTile(
              name: _socket.opponentName,
              score: _state.scoreOf(1 - me),
              clues: _state.cluesOf(1 - me),
              accent: Colors.orangeAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlash() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Text(
        _flash!,
        textAlign: TextAlign.center,
        style: TextStyle(color: _flashColor, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildPhaseBody() {
    return switch (_state.phase) {
      'countdown' => Padding(
          padding: const EdgeInsets.only(top: 80),
          child: Column(
            children: [
              Text(
                '${_state.countdown}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.w900),
              ),
              const Text('Yol açılıyor',
                  style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      'answering' => _buildAnswering(),
      'round_over' => _buildRoundOver(),
      _ => const Padding(
          padding: EdgeInsets.only(top: 80),
          child: Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent)),
        ),
    };
  }

  Widget _buildAnswering() {
    final me = _socket.mySlot;
    final attemptsLeft = _state.attemptsOf(me);
    final canAnswer = attemptsLeft > 0 && _state.roundWinner == null;
    final path = _state.pathFor(me);
    final canClue = _state.cluesOf(me) > 0 &&
        path.any((s) => s == null) &&
        _state.roundWinner == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        children: [
          _TimerBar(seconds: _state.countdown, total: _answerSeconds),
          const SizedBox(height: 14),
          _CareerTimeline(stops: path, highlight: _justRevealed),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ...List.generate(5, (i) {
                final used = i >= attemptsLeft;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(
                    used ? Icons.favorite_border : Icons.favorite,
                    color: used ? Colors.white24 : Colors.redAccent,
                    size: 16,
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: PlayerSuggestionField(
              controller: _answerController,
              enabled: canAnswer,
              autofocus: true,
              hint: 'Bu kim?',
              accent: GameMode.careerPath.colors.last,
              onSubmit: _submitGuess,
            ),
          ),
          const SizedBox(height: 12),
          _ClueButton(
            cluesLeft: _state.cluesOf(me),
            enabled: canClue,
            onTap: _useClue,
          ),
        ],
      ),
    );
  }

  Widget _buildRoundOver() {
    final winner = _state.roundWinner;
    final iWon = winner == _socket.mySlot;
    final path = _state.pathFor(_socket.mySlot);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        children: [
          NeonPanel(
            colors: winner == null
                ? const [Color(0xFF616161), Color(0xFF424242)]
                : iWon
                    ? const [Color(0xFF11998E), Color(0xFF38EF7D)]
                    : const [Color(0xFFFF512F), Color(0xFFDD2476)],
            child: Column(
              children: [
                if (_state.solutionImage != null)
                  PlayerAvatar(
                      name: _state.solution ?? '?',
                      imageUrl: _state.solutionImage,
                      size: 72),
                const SizedBox(height: 8),
                Text(
                  _state.solution ?? '?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900),
                ),
                if (_state.solutionNationality != null)
                  Text(
                    CountryCatalog.turkish(_state.solutionNationality),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                const SizedBox(height: 8),
                Text(
                  winner == null
                      ? 'Kimse bilemedi'
                      : iWon
                          ? 'Turu sen aldın'
                          : 'Turu rakibin aldı',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _CareerTimeline(stops: path, highlight: null),
          const SizedBox(height: 10),
          const Text('Sonraki tur başlıyor...',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Kulüp yolu — dikey zaman çizgisi. Gizli duraklar soru işaretiyle.
class _CareerTimeline extends StatelessWidget {
  const _CareerTimeline({required this.stops, required this.highlight});

  final List<CareerStop?> stops;
  final int? highlight;

  @override
  Widget build(BuildContext context) {
    if (stops.isEmpty) {
      return const SizedBox(height: 60);
    }
    return Column(
      children: [
        for (var i = 0; i < stops.length; i++)
          _StopRow(
            index: i,
            stop: stops[i],
            isLast: i == stops.length - 1,
            highlighted: highlight == i,
          ),
      ],
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.index,
    required this.stop,
    required this.isLast,
    required this.highlighted,
  });

  final int index;
  final CareerStop? stop;
  final bool isLast;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final revealed = stop != null;
    final dotColor = revealed
        ? (highlighted ? Colors.cyanAccent : Colors.greenAccent)
        : Colors.white24;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlighted
            ? Colors.cyanAccent.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor,
                      boxShadow: revealed
                          ? [
                              BoxShadow(
                                  color: dotColor.withValues(alpha: 0.6),
                                  blurRadius: 8)
                            ]
                          : null,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(width: 2, color: Colors.white12),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: revealed
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stop!.club,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15),
                          ),
                          Text(
                            stop!.years,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Container(
                            width: 120,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('?',
                              style: TextStyle(
                                  color: Colors.white38,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClueButton extends StatelessWidget {
  const _ClueButton(
      {required this.cluesLeft, required this.enabled, required this.onTap});

  final int cluesLeft;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(Icons.lightbulb_rounded,
          size: 18, color: enabled ? Colors.amberAccent : Colors.white24),
      label: Text(
        cluesLeft > 0 ? 'İPUCU ($cluesLeft kaldı)' : 'İPUCU BİTTİ',
        style: TextStyle(
          color: enabled ? Colors.amberAccent : Colors.white24,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 1.1,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        backgroundColor: Colors.white10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _ScoreTile extends StatelessWidget {
  const _ScoreTile({
    required this.name,
    required this.score,
    required this.clues,
    required this.accent,
  });

  final String name;
  final int score;
  final int clues;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
                Row(
                  children: List.generate(
                    3,
                    (i) => Icon(Icons.lightbulb,
                        size: 11,
                        color: i < clues ? Colors.amberAccent : Colors.white24),
                  ),
                ),
              ],
            ),
          ),
          Text('$score',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _TimerBar extends StatelessWidget {
  const _TimerBar({required this.seconds, required this.total});

  final int seconds;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = (seconds / total).clamp(0.0, 1.0);
    final low = seconds <= 10;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation(
                low ? Colors.redAccent : Colors.cyanAccent),
          ),
        ),
        const SizedBox(height: 4),
        Text('$seconds sn',
            style: TextStyle(
                color: low ? Colors.redAccent : Colors.white54, fontSize: 11)),
      ],
    );
  }
}
