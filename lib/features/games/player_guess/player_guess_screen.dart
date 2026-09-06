import 'dart:async';

import 'package:flutter/material.dart';

import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/models/room_models.dart';
import 'package:footttball/data/services/api_service.dart';
import 'package:footttball/data/services/country_catalog.dart';
import 'package:footttball/data/services/game_socket.dart';
import 'package:footttball/features/modes/mode_select_screen.dart';
import 'package:footttball/shared/widgets/app_background.dart';
import 'package:footttball/shared/widgets/game_dialogs.dart';
import 'package:footttball/shared/widgets/player_avatar.dart';
import 'package:footttball/shared/widgets/player_suggestion_field.dart';
import 'package:footttball/shared/widgets/connection_banner.dart';

/// Oyuncu Tahmin modu.
///
/// Her turda oyunculardan biri milli takımı, diğeri kulübü seçer; ardından
/// eşleşmeye uyan futbolcuyu ilk bilen turu kazanır.
class PlayerGuessScreen extends StatefulWidget {
  const PlayerGuessScreen({super.key});

  @override
  State<PlayerGuessScreen> createState() => _PlayerGuessScreenState();
}

class _PlayerGuessScreenState extends State<PlayerGuessScreen> {
  final _socket = GameSocket.instance;
  final _answerController = TextEditingController();
  StreamSubscription<SocketEvent>? _subscription;

  DuelState _state = DuelState.empty;
  String? _flash;
  Color _flashColor = Colors.redAccent;
  Timer? _flashTimer;
  bool _gameOver = false;

  @override
  void initState() {
    super.initState();
    _state = DuelState.fromJson(_socket.lastState);
    _subscription = _socket.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _flashTimer?.cancel();
    _answerController.dispose();
    super.dispose();
  }

  bool get _iPickNation => _state.nationPicker == _socket.mySlot;
  bool get _iPickClub => _state.clubPicker == _socket.mySlot;

  void _onEvent(SocketEvent event) {
    if (!mounted) return;

    switch (event.type) {
      // Yeniden bağlanan oyuncu durumu `start` ile de alabilir.
      case 'start':
      case 'state':
        setState(() => _state = DuelState.fromJson(event.payload));
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
    final answer = event.value<String>('answer') ?? '';

    switch (event.event) {
      case 'correct_answer':
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
          _showFlash('Yanlış! Kalan hakkın: $left', Colors.redAccent);
          _answerController.clear();
        }
        break;

      case 'pick_complete':
        _showFlash(
          '${event.value<String>('nation')} × ${event.value<String>('club')}',
          Colors.cyanAccent,
        );
        break;
    }
  }

  void _onGameOver(SocketEvent event) {
    if (_gameOver) return;
    _gameOver = true;

    final winner = event.value<int>('winner');
    final myScore = _state.scoreOf(_socket.mySlot);
    final rivalScore = _state.scoreOf(_socket.opponentSlot);

    GameDialogs.showInfo(
      context,
      title: winner == null
          ? 'BERABERE'
          : (winner == _socket.mySlot ? 'KAZANDIN' : 'KAYBETTİN'),
      message: 'Maç sonucu  $myScore - $rivalScore',
      actionLabel: '🏠  MENÜYE DÖN',
      onDismiss: _exitToMenu,
    );
  }

  void _showFlash(String message, Color color) {
    _flashTimer?.cancel();
    setState(() {
      _flash = message;
      _flashColor = color;
    });
    _flashTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _pick(String value) => _socket.action('pick', value: value);

  void _submitGuess(String guess) {
    final answer = guess.trim();
    if (answer.isEmpty) return;
    _socket.action('guess', value: answer);
    _answerController.clear();
  }

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
            GameBackground(accent: GameMode.playerGuess.colors.first),
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
            // Bağlantı kopunca oyunu bitirmek yerine durum gösterilir.
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
          GlassBackButton(onTap: _exitToMenu),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: GameMode.playerGuess.colors),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              // Seriyi turu ilk `totalRounds` kez kazanan alır; "3/5"
              // gösterimi bunu sabit uzunlukta bir maç gibi okutuyordu.
              '${_state.round}. TUR  •  İLK ${_state.totalRounds}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreboard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
      child: Row(
        children: [
          Expanded(
            child: _ScoreTile(
              name: _socket.myName,
              score: _state.scoreOf(_socket.mySlot),
              accent: Colors.cyanAccent,
              attemptsLeft: _state.phase == 'answering'
                  ? _state.attemptsOf(_socket.mySlot)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ScoreTile(
              name: _socket.opponentName,
              score: _state.scoreOf(_socket.opponentSlot),
              accent: Colors.purpleAccent,
              attemptsLeft: _state.phase == 'answering'
                  ? _state.attemptsOf(_socket.opponentSlot)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlash() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _flashColor.withOpacity(0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _flashColor.withOpacity(0.5)),
      ),
      child: Text(
        _flash!,
        textAlign: TextAlign.center,
        style: TextStyle(
            color: _flashColor, fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildPhaseBody() {
    return switch (_state.phase) {
      'countdown' => _CountdownView(
          seconds: _state.countdown,
          title: 'HAZIR OL',
          subtitle: 'Seçim ekranı açılıyor',
        ),
      'picking' => _buildPicking(),
      'revealing' => _CountdownView(
          seconds: _state.countdown,
          title: 'BAŞLIYOR',
          subtitle:
              '${CountryCatalog.turkish(_state.selectedNation)} × ${_state.selectedClub ?? '?'}',
        ),
      'answering' => _buildAnswering(),
      'round_over' => _buildRoundOver(),
      _ => const Padding(
          padding: EdgeInsets.only(top: 80),
          child: Center(
            child: CircularProgressIndicator(color: Colors.cyanAccent),
          ),
        ),
    };
  }

  Widget _buildPicking() {
    final myTurn = _iPickNation || _iPickClub;
    final options = _iPickNation ? _state.nations : _state.clubs;
    final alreadyPicked = (_iPickNation && _state.selectedNation != null) ||
        (_iPickClub && _state.selectedClub != null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        children: [
          Text(
            myTurn
                ? (_iPickNation ? 'MİLLİ TAKIMINI SEÇ' : 'KULÜBÜNÜ SEÇ')
                : 'RAKİBİN SEÇİYOR',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_state.countdown} saniye',
            style: const TextStyle(color: Colors.amberAccent, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (!myTurn)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Column(
                children: [
                  const CircularProgressIndicator(color: Colors.purpleAccent),
                  const SizedBox(height: 16),
                  Text(
                    _iPickNation
                        ? 'Rakibin kulübü seçiyor...'
                        : 'Rakibin milli takımı seçiyor...',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            )
          else
            ...options.map(
              (option) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PickTile(
                  label: option,
                  isNation: _iPickNation,
                  disabled: alreadyPicked,
                  selected: option ==
                      (_iPickNation
                          ? _state.selectedNation
                          : _state.selectedClub),
                  onTap: () => _pick(option),
                ),
              ),
            ),
          const SizedBox(height: 10),
          _OpponentPickStatus(state: _state, mySlot: _socket.mySlot),
        ],
      ),
    );
  }

  Widget _buildAnswering() {
    final attemptsLeft = _state.attemptsOf(_socket.mySlot);
    final canAnswer = attemptsLeft > 0 && _state.roundWinner == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        children: [
          _MatchupCard(
            nation: _state.selectedNation ?? '?',
            club: _state.selectedClub ?? '?',
          ),
          const SizedBox(height: 14),
          _TimerBar(seconds: _state.countdown, total: 30),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (index) {
              final used = index >= attemptsLeft;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  used ? Icons.favorite_border : Icons.favorite,
                  color: used ? Colors.white24 : Colors.redAccent,
                  size: 20,
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            canAnswer ? 'Deneme hakkın: $attemptsLeft' : 'Deneme hakkın bitti',
            style: TextStyle(
              color: canAnswer ? Colors.white54 : Colors.redAccent,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 18),
          // Yazdıkça futbolcu önerir; seçilen isim doğrudan gönderilir.
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: PlayerSuggestionField(
              controller: _answerController,
              enabled: canAnswer,
              autofocus: true,
              hint: 'Futbolcu adını yaz...',
              accent: GameMode.playerGuess.colors.last,
              // Öneride ülke/kulüp gösterilmez; ipucu vermemeli.
              onSubmit: _submitGuess,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundOver() {
    final winner = _state.roundWinner;
    final iWon = winner == _socket.mySlot;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
      child: NeonPanel(
        colors: winner == null
            ? const [Colors.white24, Colors.white10]
            : (iWon
                ? const [Colors.greenAccent, Colors.tealAccent]
                : const [Colors.redAccent, Colors.orangeAccent]),
        child: Column(
          children: [
            Text(
              winner == null ? '⏳' : (iWon ? '🎉' : '😕'),
              style: const TextStyle(fontSize: 40),
            ),
            const SizedBox(height: 10),
            Text(
              winner == null
                  ? 'TURU KİMSE ALAMADI'
                  : (iWon ? 'TURU SEN ALDIN' : 'TURU RAKİBİN ALDI'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            if (_state.solution != null) ...[
              const SizedBox(height: 14),
              Text(
                winner == null ? 'Doğru cevaplardan biri' : 'Cevap',
                style: const TextStyle(color: Colors.white38, fontSize: 11.5),
              ),
              const SizedBox(height: 10),
              PlayerAvatar(
                name: _state.solution!,
                imageUrl: _state.solutionImage,
                size: 76,
                borderColor: Colors.amberAccent,
              ),
              const SizedBox(height: 8),
              Text(
                _state.solution!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Sonraki tur başlıyor...',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreTile extends StatelessWidget {
  const _ScoreTile({
    required this.name,
    required this.score,
    required this.accent,
    this.attemptsLeft,
  });

  final String name;
  final int score;
  final Color accent;
  final int? attemptsLeft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.52),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accent.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$score',
            style: TextStyle(
              color: accent,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(color: accent.withOpacity(0.5), blurRadius: 12)],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountdownView extends StatelessWidget {
  const _CountdownView({
    required this.seconds,
    required this.title,
    required this.subtitle,
  });

  final int seconds;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 50),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 24),
          TweenAnimationBuilder<double>(
            key: ValueKey(seconds),
            tween: Tween(begin: 1.35, end: 1),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: GameMode.playerGuess.colors),
                boxShadow: [
                  BoxShadow(
                    color: GameMode.playerGuess.colors.last.withOpacity(0.55),
                    blurRadius: 34,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '$seconds',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 58,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.label,
    required this.isNation,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final String label;
  final bool isNation;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = isNation ? Colors.cyanAccent : Colors.purpleAccent;

    return Opacity(
      opacity: disabled && !selected ? 0.4 : 1,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: selected
                ? accent.withOpacity(0.3)
                : Colors.black.withOpacity(0.55),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accent : accent.withOpacity(0.3),
              width: selected ? 2 : 1.2,
            ),
            boxShadow: selected
                ? [BoxShadow(color: accent.withOpacity(0.4), blurRadius: 16)]
                : null,
          ),
          child: Row(
            children: [
              if (!isNation)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    ApiService.logoUrl(label),
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.shield_outlined, color: accent, size: 26),
                  ),
                )
              else
                CountryFlag(country: label, width: 34),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  isNation ? CountryCatalog.turkish(label) : label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check_circle, color: accent, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpponentPickStatus extends StatelessWidget {
  const _OpponentPickStatus({required this.state, required this.mySlot});

  final DuelState state;
  final int mySlot;

  @override
  Widget build(BuildContext context) {
    final rivalPicked = state.nationPicker == mySlot
        ? state.selectedClub != null
        : state.selectedNation != null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          rivalPicked ? Icons.check_circle : Icons.hourglass_top_rounded,
          color: rivalPicked ? Colors.greenAccent : Colors.white38,
          size: 15,
        ),
        const SizedBox(width: 7),
        Text(
          rivalPicked ? 'Rakibin seçimini yaptı' : 'Rakibin henüz seçmedi',
          style: TextStyle(
            color: rivalPicked ? Colors.greenAccent : Colors.white38,
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }
}

class _MatchupCard extends StatelessWidget {
  const _MatchupCard({required this.nation, required this.club});

  final String nation;
  final String club;

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      colors: GameMode.playerGuess.colors,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                CountryFlag(country: nation, width: 46),
                const SizedBox(height: 8),
                Text(
                  CountryCatalog.turkish(nation),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Text('×',
              style: TextStyle(color: Colors.white38, fontSize: 22)),
          Expanded(
            child: Column(
              children: [
                Image.network(
                  ApiService.logoUrl(club),
                  width: 34,
                  height: 34,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.shield_outlined,
                    color: Colors.purpleAccent,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  club,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
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

class _TimerBar extends StatelessWidget {
  const _TimerBar({required this.seconds, required this.total});

  final int seconds;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = (seconds / total).clamp(0.0, 1.0);
    final low = seconds <= 8;

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation(
              low ? Colors.redAccent : Colors.cyanAccent,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$seconds sn',
          style: TextStyle(
            color: low ? Colors.redAccent : Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
