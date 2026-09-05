import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:footttball/core/session.dart';
import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/models/room_models.dart';
import 'package:footttball/data/services/game_socket.dart';
import 'package:footttball/features/lobby/vs_screen.dart';
import 'package:footttball/shared/widgets/app_background.dart';

/// Rakip beklenen oda ekranı. Bağlantıyı kurar ve oyun başlayınca yönlendirir.
class WaitingRoomScreen extends StatefulWidget {
  const WaitingRoomScreen({
    super.key,
    required this.roomCode,
    required this.mode,
    required this.isHost,
  });

  final String roomCode;
  final GameMode mode;
  final bool isHost;

  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen> {
  final _socket = GameSocket.instance;
  StreamSubscription<SocketEvent>? _subscription;

  List<RoomPlayer> _players = const [];
  String? _error;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    _socket.clearCallbacks();
    _subscription = _socket.events.listen(_onEvent);

    try {
      await _socket.connect(
        code: widget.roomCode,
        name: Session.instance.displayName,
        mode: widget.mode,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Sunucuya bağlanılamadı. Bağlantını kontrol et.');
    }
  }

  void _onEvent(SocketEvent event) {
    if (!mounted) return;

    switch (event.type) {
      case 'joined':
      case 'room':
        setState(() => _players = _socket.players);
        break;

      case 'start':
        _goToGame();
        break;

      case 'error':
        setState(() => _error = event.value<String>('message') ?? 'Beklenmeyen bir hata oluştu.');
        break;

      case 'closed':
        if (!_navigated) {
          setState(() => _error = 'Bağlantı kapandı.');
        }
        break;
    }
  }

  void _goToGame() {
    if (_navigated) return;
    _navigated = true;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => VsScreen(mode: widget.mode)),
    );
  }

  Future<void> _leave() async {
    _socket.leave();
    await _socket.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    // Oyuna geçiliyorsa bağlantı korunur; aksi halde kapatılır.
    if (!_navigated) _socket.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: Stack(
          alignment: Alignment.center,
          children: [
            const AppBackground(dim: 0.45),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: GlassBackButton(onTap: _leave),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  _ModePill(mode: widget.mode),
                  const SizedBox(height: 26),
                  _RoomCodeCard(code: widget.roomCode),
                  const SizedBox(height: 34),
                  if (_error != null)
                    _ErrorCard(message: _error!, onExit: _leave)
                  else ...[
                    _PlayerSlots(players: _players, mySlot: _socket.mySlot),
                    const SizedBox(height: 30),
                    const NeonTitle('RAKİP BEKLENİYOR', fontSize: 19),
                    const SizedBox(height: 24),
                    const _BouncingBalls(),
                  ],
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 34),
                    child: Text(
                      'Maçı başlatmak için bu kodu paylaş',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.38),
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({required this.mode});

  final GameMode mode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: mode.colors),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: mode.colors.last.withOpacity(0.4), blurRadius: 16),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(mode.icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            mode.title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomCodeCard extends StatelessWidget {
  const _RoomCodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 22),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.28),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'ODA KODU',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              letterSpacing: 3,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            code,
            style: const TextStyle(
              fontSize: 46,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 5,
              shadows: [Shadow(color: Colors.purpleAccent, blurRadius: 15)],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerSlots extends StatelessWidget {
  const _PlayerSlots({required this.players, required this.mySlot});

  final List<RoomPlayer> players;
  final int mySlot;

  @override
  Widget build(BuildContext context) {
    RoomPlayer? at(int slot) =>
        players.where((player) => player.slot == slot).cast<RoomPlayer?>().firstOrNull;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _slot(at(0), isMe: mySlot == 0, color: Colors.cyanAccent),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'VS',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 17,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        _slot(at(1), isMe: mySlot == 1, color: Colors.purpleAccent),
      ],
    );
  }

  Widget _slot(RoomPlayer? player, {required bool isMe, required Color color}) {
    final filled = player != null;
    return Container(
      width: 118,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: filled ? color.withOpacity(0.7) : Colors.white12,
          width: 1.6,
        ),
      ),
      child: Column(
        children: [
          Icon(
            filled ? Icons.person : Icons.person_outline,
            color: filled ? color : Colors.white24,
            size: 26,
          ),
          const SizedBox(height: 7),
          Text(
            filled ? player.name : 'Bekleniyor',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: filled ? Colors.white : Colors.white38,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (isMe) ...[
            const SizedBox(height: 3),
            Text(
              'SEN',
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onExit});

  final String message;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: NeonPanel(
        colors: const [Colors.redAccent, Colors.orangeAccent],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🚫', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.4),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'GERİ DÖN',
              colors: const [Colors.redAccent, Colors.orangeAccent],
              onTap: onExit,
            ),
          ],
        ),
      ),
    );
  }
}

class _BouncingBalls extends StatefulWidget {
  const _BouncingBalls();

  @override
  State<_BouncingBalls> createState() => _BouncingBallsState();
}

class _BouncingBallsState extends State<_BouncingBalls>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (index) {
          final value = (_controller.value + index * 0.2) % 1.0;
          final bounce = math.sin(value * math.pi);

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                Transform.translate(
                  offset: Offset(0, -20 * bounce),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.3 * bounce),
                          blurRadius: 10 * bounce,
                          spreadRadius: 2 * bounce,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.sports_soccer, color: Colors.white, size: 30),
                  ),
                ),
                const SizedBox(height: 5),
                Opacity(
                  opacity: 1.0 - bounce * 0.7,
                  child: Transform.scale(
                    scale: 1.0 - bounce * 0.5,
                    child: Container(
                      width: 20,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
