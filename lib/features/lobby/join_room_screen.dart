import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:footttball/core/session.dart';
import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/services/api_service.dart';
import 'package:footttball/features/lobby/waiting_room_screen.dart';
import 'package:footttball/shared/widgets/app_background.dart';
import 'package:footttball/shared/widgets/game_dialogs.dart';

/// Oda koduyla mevcut bir odaya katılma ekranı.
class JoinRoomScreen extends StatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen>
    with TickerProviderStateMixin {
  static const _codeLength = 4;

  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _glow;
  late final AnimationController _shake;

  bool _checking = false;

  GameMode get _mode => Session.instance.selectedMode;
  String get _code => _controller.text;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _controller.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _glow.dispose();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final digits = (data?.text ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    _controller.text = digits.substring(0, digits.length.clamp(0, _codeLength));
    _focus.requestFocus();
  }

  void _reject(String title, String message) {
    _shake.forward(from: 0);
    GameDialogs.showWarning(context, title: title, message: message);
  }

  Future<void> _join() async {
    final code = _code.trim();

    if (code.length < _codeLength) {
      _reject('KOD EKSİK', 'Odaya katılmak için $_codeLength haneli kodu gir.');
      return;
    }

    setState(() => _checking = true);
    _focus.unfocus();

    try {
      final status = await ApiService.roomStatus(code);
      if (!mounted) return;
      setState(() => _checking = false);

      if (!status.exists) {
        _reject('ODA BULUNAMADI',
            '"$code" kodlu bir oda yok.\nKurucudan kodu tekrar iste.');
        return;
      }

      if (!status.joinable) {
        _reject('ODA DOLU', 'Bu odada zaten iki oyuncu var.');
        return;
      }

      // Oda başka bir oyun modunda kurulmuşsa katılım engellenir; aksi halde
      // oyuncu seçtiğinden farklı bir oyunun içinde buluyordu kendini.
      final roomMode = status.mode;
      if (roomMode != null && roomMode != _mode) {
        _reject(
          'FARKLI OYUN MODU',
          '"$code" kodlu oda ${roomMode.title} modunda kurulmuş.\n'
              'Sen ${_mode.title} seçtin.\n\n'
              'Menüye dönüp ${roomMode.title} modunu seçerek katılabilirsin.',
        );
        return;
      }

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WaitingRoomScreen(
            roomCode: code,
            mode: roomMode ?? _mode,
            isHost: false,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _checking = false);
      _reject('BAĞLANTI HATASI',
          'Sunucuya ulaşılamadı.\nİnternet bağlantını kontrol et.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _mode.colors.last;
    final complete = _code.length == _codeLength;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          PlainBackground(accent: _mode.colors.first),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      GlassBackButton(
                          onTap: () => Navigator.of(context).maybePop()),
                      const Spacer(),
                      _ModeChip(mode: _mode),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 24),
                        _buildIcon(accent),
                        const SizedBox(height: 22),
                        NeonTitle(
                          'ODA KODUNU GİR',
                          fontSize: 24,
                          colors: [Colors.white, accent],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Arkadaşının odasında beliren $_codeLength haneli kod',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 30),
                        _buildCodeBoxes(accent, complete),
                        const SizedBox(height: 18),
                        _buildPasteButton(),
                        const SizedBox(height: 32),
                        if (_checking)
                          Column(
                            children: [
                              CircularProgressIndicator(color: accent),
                              const SizedBox(height: 14),
                              Text(
                                'Oda kontrol ediliyor...',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          )
                        else
                          PrimaryButton(
                            label: 'ODAYA KATIL',
                            icon: Icons.login_rounded,
                            enabled: complete,
                            colors: _mode.colors,
                            onTap: _join,
                          ),
                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Kod girişi görünmez bir alanla yapılır; kutular onu yansıtır.
          Positioned(
            left: 0,
            width: 1,
            height: 1,
            top: 0,
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                keyboardType: TextInputType.number,
                maxLength: _codeLength,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _join(),
                onChanged: (value) {
                  if (value.length == _codeLength) _focus.unfocus();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIcon(Color accent) {
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.2 + 0.18 * _glow.value),
              blurRadius: 34 + 14 * _glow.value,
              spreadRadius: 2,
            ),
          ],
        ),
        child: child,
      ),
      child: Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: _mode.colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 2),
        ),
        child: const Icon(Icons.vpn_key_rounded, color: Colors.white, size: 34),
      ),
    );
  }

  /// Dört haneli kutu göstergesi; dokununca klavye açılır.
  Widget _buildCodeBoxes(Color accent, bool complete) {
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        // Hatalı kodda kutular kısa süre titrer.
        final t = _shake.value;
        final offset =
            t == 0 ? 0.0 : 10 * (1 - t) * ((t * 8).floor().isEven ? 1 : -1);
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: GestureDetector(
        onTap: () => _focus.requestFocus(),
        behavior: HitTestBehavior.opaque,
        // Dört kutu dar ekranlara sığmıyordu; birlikte küçülürler.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_codeLength, (index) {
              final filled = index < _code.length;
              final active = index == _code.length && _focus.hasFocus;
              final digit = filled ? _code[index] : '';

              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 6),
                width: 62,
                height: 78,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(filled ? 0.5 : 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: filled
                        ? accent
                        : (active ? accent.withOpacity(0.7) : Colors.white12),
                    width: filled || active ? 2 : 1.3,
                  ),
                  boxShadow: filled
                      ? [
                          BoxShadow(
                              color: accent.withOpacity(0.3), blurRadius: 14)
                        ]
                      : null,
                ),
                child: Center(
                  child: filled
                      ? Text(
                          digit,
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            shadows: [Shadow(color: accent, blurRadius: 12)],
                          ),
                        )
                      : AnimatedOpacity(
                          opacity: active ? 1 : 0.25,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            width: 18,
                            height: 3,
                            decoration: BoxDecoration(
                              color: active ? accent : Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildPasteButton() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton.icon(
          onPressed: _paste,
          icon: const Icon(Icons.content_paste_rounded,
              size: 16, color: Colors.white54),
          label: const Text(
            'Panodan yapıştır',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
        if (_code.isNotEmpty)
          TextButton.icon(
            onPressed: () {
              _controller.clear();
              _focus.requestFocus();
            },
            icon: const Icon(Icons.backspace_outlined,
                size: 16, color: Colors.white54),
            label: const Text(
              'Temizle',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.mode});

  final GameMode mode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: mode.colors),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: mode.colors.last.withOpacity(0.35), blurRadius: 14),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(mode.icon, color: Colors.white, size: 15),
          const SizedBox(width: 7),
          Text(
            mode.title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
