import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class _WaitingRoomScreenState extends State<WaitingRoomScreen>
    with TickerProviderStateMixin {
  final _socket = GameSocket.instance;
  StreamSubscription<SocketEvent>? _subscription;

  late final AnimationController _pulse;
  late final AnimationController _orbit;

  List<RoomPlayer> _players = const [];
  String? _error;
  bool _navigated = false;
  bool _copied = false;
  Timer? _copyTimer;

  Color get _accent => widget.mode.colors.last;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
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
        setState(() => _error =
            event.value<String>('message') ?? 'Beklenmeyen bir hata oluştu.');
        break;

      case 'closed':
        if (!_navigated) setState(() => _error = 'Bağlantı kapandı.');
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

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.roomCode));
    if (!mounted) return;
    setState(() => _copied = true);
    _copyTimer?.cancel();
    _copyTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _leave() async {
    _socket.leave();
    await _socket.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _copyTimer?.cancel();
    _pulse.dispose();
    _orbit.dispose();
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
          children: [
            PlainBackground(accent: widget.mode.colors.first),
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      child: _error != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 60),
                              child:
                                  _ErrorCard(message: _error!, onExit: _leave),
                            )
                          : Column(
                              children: [
                                _buildCodeCard(),
                                const SizedBox(height: 22),
                                _buildPlayers(),
                                const SizedBox(height: 22),
                                _buildStatus(),
                                const SizedBox(height: 22),
                                _RulesCard(mode: widget.mode),
                              ],
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          GlassBackButton(onTap: _leave),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: widget.mode.colors),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(color: _accent.withOpacity(0.4), blurRadius: 16),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.mode.icon, color: Colors.white, size: 17),
                const SizedBox(width: 8),
                Text(
                  widget.mode.title.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Oda kodu — dokununca panoya kopyalanır.
  Widget _buildCodeCard() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final glow = 0.25 + 0.25 * _pulse.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: _accent.withOpacity(glow),
                blurRadius: 26 + 10 * _pulse.value,
                spreadRadius: 1,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF16132C).withOpacity(0.92),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _accent.withOpacity(0.55), width: 1.8),
        ),
        child: Column(
          children: [
            Text(
              'ODA KODU',
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 11.5,
                letterSpacing: 3.4,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: widget.roomCode.split('').map((digit) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  width: 54,
                  height: 68,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: _accent.withOpacity(0.4), width: 1.4),
                  ),
                  child: Center(
                    child: Text(
                      digit,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        shadows: [Shadow(color: _accent, blurRadius: 14)],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _copyCode,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                decoration: BoxDecoration(
                  color: _copied
                      ? Colors.greenAccent.withOpacity(0.18)
                      : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _copied
                        ? Colors.greenAccent.withOpacity(0.7)
                        : Colors.white.withOpacity(0.18),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _copied ? Icons.check_rounded : Icons.copy_rounded,
                      color: _copied ? Colors.greenAccent : Colors.white70,
                      size: 17,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _copied ? 'Kopyalandı' : 'Kodu kopyala',
                      style: TextStyle(
                        color: _copied ? Colors.greenAccent : Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayers() {
    RoomPlayer? at(int slot) => _players
        .where((player) => player.slot == slot)
        .cast<RoomPlayer?>()
        .firstOrNull;

    final me = at(_socket.mySlot);
    final rival = at(_socket.opponentSlot);

    return Row(
      children: [
        Expanded(
          child: _PlayerCard(
            name: me?.name ?? Session.instance.displayName,
            label: 'SEN',
            accent: Colors.cyanAccent,
            filled: true,
            orbit: _orbit,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'VS',
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 18,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        Expanded(
          child: _PlayerCard(
            name: rival?.name ?? 'Bekleniyor',
            label: rival == null ? 'BOŞ' : 'RAKİP',
            accent: _accent,
            filled: rival != null,
            orbit: _orbit,
          ),
        ),
      ],
    );
  }

  Widget _buildStatus() {
    final waiting = _players.length < 2;

    return Column(
      children: [
        NeonTitle(
          waiting ? 'RAKİP BEKLENİYOR' : 'HERKES HAZIR',
          fontSize: 18,
          colors: waiting
              ? [Colors.white, _accent]
              : const [Colors.white, Colors.greenAccent],
        ),
        const SizedBox(height: 10),
        if (waiting)
          _TypingDots(controller: _orbit, color: _accent)
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle,
                  color: Colors.greenAccent, size: 16),
              const SizedBox(width: 8),
              Text(
                'Oyun başlıyor...',
                style: TextStyle(
                  color: Colors.greenAccent.withOpacity(0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        const SizedBox(height: 10),
        Text(
          waiting
              ? 'Kodu arkadaşınla paylaş, o katılınca maç başlasın'
              : 'İyi şanslar!',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.42),
            fontSize: 12.5,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

/// Oyuncu yeri. Boş yer, dönen halkayla "bekleniyor" hissi verir.
class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.name,
    required this.label,
    required this.accent,
    required this.filled,
    required this.orbit,
  });

  final String name;
  final String label;
  final Color accent;
  final bool filled;
  final AnimationController orbit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(filled ? 0.5 : 0.32),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: filled ? accent.withOpacity(0.75) : Colors.white12,
          width: filled ? 1.8 : 1.2,
        ),
        boxShadow: filled
            ? [BoxShadow(color: accent.withOpacity(0.28), blurRadius: 16)]
            : null,
      ),
      child: Column(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!filled)
                  AnimatedBuilder(
                    animation: orbit,
                    builder: (context, _) => Transform.rotate(
                      angle: orbit.value * 2 * math.pi,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            colors: [
                              Colors.transparent,
                              accent.withOpacity(0.55),
                              Colors.transparent,
                            ],
                            stops: const [0.35, 0.6, 0.85],
                          ),
                        ),
                      ),
                    ),
                  ),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.55),
                    border: Border.all(
                      color: filled ? accent : Colors.white24,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    filled ? Icons.person : Icons.person_search_rounded,
                    color: filled ? accent : Colors.white30,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: filled ? Colors.white : Colors.white38,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: filled ? accent : Colors.white24,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Modun kurallarını özetleyen kart — bekleme süresini bilgiyle doldurur.
class _RulesCard extends StatelessWidget {
  const _RulesCard({required this.mode});

  final GameMode mode;

  List<(IconData, String)> get _rules => switch (mode) {
        GameMode.tikiTakaToe => [
            (
              Icons.grid_3x3_rounded,
              'Kulüp ve millet kesişimine uyan futbolcuyu yaz'
            ),
            (Icons.timer_outlined, 'Her hamle için 30 saniyen var'),
            (Icons.swap_horiz_rounded, 'Rakibin kutusunu çalma hakkın 3 kez'),
          ],
        GameMode.playerGuess => [
            (
              Icons.flag_rounded,
              'Biriniz milli takımı, diğeriniz kulübü seçer'
            ),
            (
              Icons.bolt_rounded,
              'Eşleşmeye uyan futbolcuyu ilk bilen turu alır'
            ),
            (Icons.favorite_rounded, 'Tur başına 3 deneme hakkın var'),
          ],
        GameMode.lastLetter => [
            (Icons.abc_rounded, 'Rakibinin yazdığı ismin son harfiyle başla'),
            (Icons.hourglass_bottom_rounded, 'Oyuncu başına 50 saniye'),
            (Icons.remove_circle_outline, 'Yanlış cevap 3 saniye götürür'),
          ],
        GameMode.categoryRace => [
            (
              Icons.category_rounded,
              'Verilen kategoriye uyan futbolcuları yaz'
            ),
            (
              Icons.hourglass_bottom_rounded,
              'Sırayla oynanır, herkesin 50 saniyesi var'
            ),
            (
              Icons.remove_circle_outline,
              'Yanlış ya da tekrar eden isim 3 saniye götürür'
            ),
          ],
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: mode.colors.last.withOpacity(0.9), size: 16),
              const SizedBox(width: 8),
              Text(
                'NASIL OYNANIR',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._rules.map((rule) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: mode.colors.last.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(rule.$1, color: mode.colors.last, size: 15),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        rule.$2,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.78),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

/// Sıralı yanıp sönen üç nokta.
class _TypingDots extends StatelessWidget {
  const _TypingDots({required this.controller, required this.color});

  final AnimationController controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (index) {
          final phase = (controller.value + index * 0.22) % 1.0;
          final wave = math.sin(phase * math.pi).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Transform.translate(
              offset: Offset(0, -5 * wave),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.35 + 0.55 * wave),
                  boxShadow: [
                    BoxShadow(
                        color: color.withOpacity(0.5 * wave), blurRadius: 10),
                  ],
                ),
              ),
            ),
          );
        }),
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
    return NeonPanel(
      colors: const [Colors.redAccent, Colors.orangeAccent],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🚫', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 14.5, height: 1.4),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'GERİ DÖN',
            colors: const [Colors.redAccent, Colors.orangeAccent],
            onTap: onExit,
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
