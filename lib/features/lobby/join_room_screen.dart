import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:footttball/core/session.dart';
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
    with SingleTickerProviderStateMixin {
  final _codeController = TextEditingController();
  late final AnimationController _glowController;
  late final Animation<double> _glow;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _glow = Tween<double>(begin: 0, end: 1).animate(_glowController);
  }

  @override
  void dispose() {
    _codeController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _codeController.text.trim();

    if (code.isEmpty) {
      GameDialogs.showWarning(
        context,
        title: 'KOD GEREKLİ',
        message: 'Devam etmek için oda kodunu gir.',
      );
      return;
    }

    setState(() => _checking = true);

    try {
      final status = await ApiService.roomStatus(code);
      if (!mounted) return;
      setState(() => _checking = false);

      if (!status.exists) {
        GameDialogs.showWarning(
          context,
          title: 'ODA BULUNAMADI',
          message: '"$code" kodlu bir oda yok.\nKurucudan kodu tekrar iste.',
        );
        return;
      }

      if (!status.joinable) {
        GameDialogs.showWarning(
          context,
          title: 'ODA DOLU',
          message: 'Bu odada zaten iki oyuncu var.',
        );
        return;
      }

      // Oda başka bir oyun modunda kurulmuşsa katılım engellenir; aksi halde
      // oyuncu seçtiğinden farklı bir oyunun içinde buluyordu kendini.
      final selected = Session.instance.selectedMode;
      final roomMode = status.mode;

      if (roomMode != null && roomMode != selected) {
        GameDialogs.showWarning(
          context,
          title: 'FARKLI OYUN MODU',
          message: '"$code" kodlu oda ${roomMode.title} modunda kurulmuş.\n'
              'Sen ${selected.title} seçtin.\n\n'
              'Menüye dönüp ${roomMode.title} modunu seçerek katılabilirsin.',
        );
        return;
      }

      final mode = roomMode ?? selected;
      Session.instance.selectedMode = mode;

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WaitingRoomScreen(
            roomCode: code,
            mode: mode,
            isHost: false,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _checking = false);
      GameDialogs.showWarning(
        context,
        title: 'BAĞLANTI HATASI',
        message: 'Sunucuya ulaşılamadı.\nİnternet bağlantını kontrol et.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const PlainBackground(accent: Colors.orangeAccent),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: GlassBackButton(onTap: () => Navigator.of(context).maybePop()),
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(top: size.height * 0.38, bottom: 40),
              child: Column(
                children: [
                  AnimatedBuilder(
                    animation: _glow,
                    builder: (context, child) => Container(
                      width: size.width * 0.75,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: const LinearGradient(
                          colors: [Colors.orangeAccent, Colors.pinkAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.pinkAccent.withOpacity(0.4 + 0.3 * _glow.value),
                            blurRadius: 15 + 10 * _glow.value,
                            spreadRadius: 1 + 3 * _glow.value,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: child,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 6,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 6,
                        ),
                        cursorColor: Colors.orangeAccent,
                        decoration: const InputDecoration(
                          counterText: '',
                          hintText: 'ODA KODU',
                          hintStyle: TextStyle(
                            color: Colors.white38,
                            fontSize: 17,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w600,
                          ),
                          prefixIcon: Icon(Icons.vpn_key_rounded, color: Colors.orangeAccent),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _join(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 46),
                  if (_checking)
                    const CircularProgressIndicator(color: Colors.amberAccent)
                  else
                    PrimaryButton(
                      label: 'ODAYA KATIL',
                      icon: Icons.login_rounded,
                      onTap: _join,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
