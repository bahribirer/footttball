import 'dart:async';

import 'package:flutter/material.dart';

import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/models/room_models.dart';
import 'package:footttball/data/services/country_catalog.dart';
import 'package:footttball/data/services/game_socket.dart';
import 'package:footttball/features/modes/mode_select_screen.dart';
import 'package:footttball/shared/widgets/app_background.dart';
import 'package:footttball/shared/widgets/game_dialogs.dart';
import 'package:footttball/shared/widgets/player_avatar.dart';

/// Son Harf ve Kategori Yarışı modlarının ortak ekran iskeleti.
///
/// Saat, sıra yönetimi, cevap gönderme ve oyun sonu akışı buradadır; her mod
/// yalnızca ortadaki bilgi panelini ve giriş ipucunu özelleştirir.
class ClockGameScaffold extends StatefulWidget {
  const ClockGameScaffold({
    super.key,
    required this.mode,
    required this.buildInfoPanel,
    required this.inputHint,
    this.emptyHistoryText = 'İlk cevabı yaz ve zinciri başlat',
  });

  final GameMode mode;

  /// Modun ortasında görünen bilgi paneli (gerekli harf / kategori).
  final Widget Function(BuildContext context, ClockGameState state) buildInfoPanel;

  final String inputHint;
  final String emptyHistoryText;

  @override
  State<ClockGameScaffold> createState() => _ClockGameScaffoldState();
}

class _ClockGameScaffoldState extends State<ClockGameScaffold> {
  final _socket = GameSocket.instance;
  final _answerController = TextEditingController();
  final _answerFocus = FocusNode();
  StreamSubscription<SocketEvent>? _subscription;
  Timer? _localTicker;

  ClockGameState _state = ClockGameState.empty;
  String? _flashMessage;
  Color _flashColor = Colors.redAccent;
  Timer? _flashTimer;
  bool _gameOver = false;
  bool _submitting = false;

  /// Sunucu saniyede bir durum yollar; aradaki süre yerelde sayılarak
  /// geri sayımın takılmadan akması sağlanır.
  double _localClockOffset = 0;

  @override
  void initState() {
    super.initState();
    _state = ClockGameState.fromJson(_socket.lastState);
    _subscription = _socket.events.listen(_onEvent);
    _localTicker = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => setState(() => _localClockOffset += 0.2),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _localTicker?.cancel();
    _flashTimer?.cancel();
    _answerController.dispose();
    _answerFocus.dispose();
    super.dispose();
  }

  bool get _isMyTurn => _state.currentTurn == _socket.mySlot;

  double _displayClock(int slot) {
    final base = _state.clockOf(slot);
    if (_gameOver || slot != _state.currentTurn) return base;
    return (base - _localClockOffset).clamp(0, base);
  }

  void _onEvent(SocketEvent event) {
    if (!mounted) return;

    switch (event.type) {
      case 'start':
      case 'state':
        setState(() {
          _state = ClockGameState.fromJson(event.payload);
          _localClockOffset = 0;
        });
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
      case 'accepted':
        if (slot != _socket.mySlot) {
          _flash('$answer ✓', Colors.greenAccent);
        } else {
          _answerController.clear();
          _flash('Kabul edildi: $answer', Colors.greenAccent);
        }
        break;

      case 'rejected':
        if (slot == _socket.mySlot) {
          _flash(_rejectionText(event.value<String>('reason')), Colors.redAccent);
        }
        break;

      case 'time_up':
        _flash(
          slot == _socket.mySlot ? 'Süren doldu!' : 'Rakibin süresi doldu!',
          Colors.orangeAccent,
        );
        break;
    }
  }

  String _rejectionText(String? reason) => switch (reason) {
        'not_found' => 'Böyle bir futbolcu bulunamadı  −3sn',
        'wrong_letter' => 'Doğru harfle başlamıyor  −3sn',
        'duplicate' => 'Bu isim daha önce yazıldı  −3sn',
        'off_category' => 'Bu futbolcu kategoriye uymuyor  −3sn',
        _ => 'Geçersiz cevap  −3sn',
      };

  void _onGameOver(SocketEvent event) {
    if (_gameOver) return;
    _gameOver = true;

    final winner = event.value<int>('winner');
    final iWon = winner == _socket.mySlot;

    GameDialogs.showInfo(
      context,
      title: iWon ? 'KAZANDIN' : (winner == null ? 'BERABERE' : 'KAYBETTİN'),
      message: iWon
          ? 'Rakibinin süresi doldu. Tebrikler!'
          : (winner == null
              ? 'Oyun berabere bitti.'
              : 'Süren doldu. Bir dahakine daha hızlı ol!'),
      actionLabel: '🏠  MENÜYE DÖN',
      onDismiss: _exitToMenu,
    );
  }

  void _flash(String message, Color color) {
    _flashTimer?.cancel();
    setState(() {
      _flashMessage = message;
      _flashColor = color;
    });
    _flashTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _flashMessage = null);
    });
  }

  Future<void> _submit() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty || !_isMyTurn || _gameOver || _submitting) return;

    setState(() => _submitting = true);
    _socket.action('answer', value: answer);
    _answerController.clear();
    _answerFocus.requestFocus();

    // Sunucu yanıtı beklenirken çift gönderim engellenir.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (mounted) setState(() => _submitting = false);
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
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            GameBackground(accent: widget.mode.colors.first),
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 8),
                  _buildClocks(),
                  const SizedBox(height: 14),
                  widget.buildInfoPanel(context, _state),
                  const SizedBox(height: 10),
                  _buildFlash(),
                  Expanded(child: _buildHistory()),
                  _buildInput(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          GlassBackButton(onTap: _confirmExit),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: widget.mode.colors),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.mode.icon, color: Colors.white, size: 15),
                const SizedBox(width: 7),
                Text(
                  widget.mode.title.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClocks() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _ClockCard(
              name: _socket.myName,
              isMe: true,
              seconds: _displayClock(_socket.mySlot),
              active: _isMyTurn && !_gameOver,
              accent: Colors.cyanAccent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ClockCard(
              name: _socket.opponentName,
              isMe: false,
              seconds: _displayClock(_socket.opponentSlot),
              active: !_isMyTurn && !_gameOver,
              accent: Colors.purpleAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlash() {
    return SizedBox(
      height: 30,
      child: AnimatedOpacity(
        opacity: _flashMessage == null ? 0 : 1,
        duration: const Duration(milliseconds: 180),
        child: _flashMessage == null
            ? const SizedBox.shrink()
            : Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _flashColor.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _flashColor.withOpacity(0.5)),
                ),
                child: Text(
                  _flashMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _flashColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHistory() {
    if (_state.history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Text(
            widget.emptyHistoryText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white30, fontSize: 13.5),
          ),
        ),
      );
    }

    final reversed = _state.history.reversed.toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
      itemCount: reversed.length,
      itemBuilder: (context, index) {
        final entry = reversed[index];
        final mine = entry.slot == _socket.mySlot;
        final accent = mine ? Colors.cyanAccent : Colors.purpleAccent;

        final latest = index == 0;
        final subtitle = [
          if (entry.country != null && entry.country!.isNotEmpty)
            CountryCatalog.turkish(entry.country),
          if (entry.club != null && entry.club!.isNotEmpty) entry.club!,
        ].join(' • ');

        return Align(
          alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 290),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: accent.withOpacity(latest ? 0.2 : 0.09),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withOpacity(latest ? 0.6 : 0.22)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PlayerAvatar(
                  name: entry.answer,
                  imageUrl: entry.imageUrl,
                  size: latest ? 42 : 34,
                  borderColor: accent,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.answer,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(latest ? 1 : 0.75),
                          fontSize: latest ? 15 : 14,
                          fontWeight: latest ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (entry.country != null && entry.country!.isNotEmpty) ...[
                              CountryFlag(country: entry.country!, width: 18),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                entry.club ?? CountryCatalog.turkish(entry.country),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.check_circle, color: accent, size: 15),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInput() {
    final enabled = _isMyTurn && !_gameOver;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.of(context).viewInsets.bottom * 0,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _answerController,
              focusNode: _answerFocus,
              enabled: enabled,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(color: Colors.white, fontSize: 15.5),
              cursorColor: Colors.cyanAccent,
              decoration: InputDecoration(
                hintText: enabled ? widget.inputHint : 'Rakibin sırası...',
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
                filled: true,
                fillColor: Colors.white.withOpacity(enabled ? 0.09 : 0.04),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: enabled ? _submit : null,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: enabled
                      ? widget.mode.colors
                      : [Colors.white12, Colors.white10],
                ),
                boxShadow: enabled
                    ? [
                        BoxShadow(
                          color: widget.mode.colors.last.withOpacity(0.5),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                Icons.send_rounded,
                color: enabled ? Colors.white : Colors.white24,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmExit() {
    if (_gameOver) {
      _exitToMenu();
      return;
    }
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: NeonPanel(
          colors: const [Colors.redAccent, Colors.orangeAccent],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🚪', style: TextStyle(fontSize: 38)),
              const SizedBox(height: 10),
              const Text(
                'Oyundan çıkmak istiyor musun?\nRakibin hükmen kazanır.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('DEVAM ET',
                        style: TextStyle(color: Colors.white60, fontWeight: FontWeight.bold)),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      _exitToMenu();
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                    child: const Text('ÇIK', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClockCard extends StatelessWidget {
  const _ClockCard({
    required this.name,
    required this.isMe,
    required this.seconds,
    required this.active,
    required this.accent,
  });

  final String name;
  final bool isMe;
  final double seconds;
  final bool active;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final low = seconds <= 10;
    final color = low ? Colors.redAccent : accent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(active ? 0.62 : 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? color.withOpacity(0.85) : Colors.white12,
          width: active ? 2 : 1,
        ),
        boxShadow: active
            ? [BoxShadow(color: color.withOpacity(0.35), blurRadius: 16)]
            : null,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                active ? Icons.play_arrow_rounded : Icons.pause_rounded,
                color: active ? color : Colors.white24,
                size: 15,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  isMe ? '$name (sen)' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? Colors.white : Colors.white54,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            seconds.ceil().toString().padLeft(2, '0'),
            style: TextStyle(
              color: color,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(color: color.withOpacity(0.6), blurRadius: 12)],
            ),
          ),
        ],
      ),
    );
  }
}
