import 'dart:async';

import 'package:flutter/material.dart';

import 'package:footttball/data/models/room_models.dart';
import 'package:footttball/data/services/game_socket.dart';

/// Bağlantı durumunu ekranın üstünde gösteren şerit.
///
/// Mobil şebekede kısa kopmalar sık yaşanıyor. Sunucu oyuncunun yerini bir
/// süre koruduğu için oyun bitmez; oyuncuya ne olduğunu anlatmak yeterlidir.
/// Oyun ekranları bunu `Stack` içine koyar.
class ConnectionBanner extends StatefulWidget {
  const ConnectionBanner({super.key});

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

enum _Status { ok, reconnecting, opponentAway, restored }

class _ConnectionBannerState extends State<ConnectionBanner> {
  StreamSubscription? _subscription;
  Timer? _hideTimer;

  _Status _status = _Status.ok;
  String _detail = '';

  @override
  void initState() {
    super.initState();
    _subscription = GameSocket.instance.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onEvent(SocketEvent event) {
    if (!mounted) return;

    switch (event.type) {
      case 'reconnecting':
        _show(_Status.reconnecting,
            'Bağlantı koptu, yeniden bağlanılıyor (${event.data['attempt']})...');
        break;

      case 'reconnected':
        _show(_Status.restored, 'Bağlantı geri geldi');
        _autoHide();
        break;

      case 'reconnect_failed':
        _show(_Status.reconnecting, 'Bağlantı kurulamadı');
        break;

      case 'event':
        final name = event.data['event'];
        if (name == 'opponent_disconnected') {
          _show(_Status.opponentAway,
              '${event.data['name'] ?? 'Rakip'} bağlantısı koptu, bekleniyor...');
        } else if (name == 'opponent_reconnected') {
          _show(
              _Status.restored, '${event.data['name'] ?? 'Rakip'} geri döndü');
          _autoHide();
        }
        break;
    }
  }

  void _show(_Status status, String detail) {
    _hideTimer?.cancel();
    setState(() {
      _status = status;
      _detail = detail;
    });
  }

  void _autoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _status = _Status.ok);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _status != _Status.ok;
    final restored = _status == _Status.restored;

    final colors = restored
        ? const [Color(0xFF00B87C), Color(0xFF00D68F)]
        : const [Color(0xFFB35A00), Color(0xFFE08A00)];

    return IgnorePointer(
      child: SafeArea(
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, -1.4),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: colors.last.withOpacity(0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (restored)
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.white, size: 17)
                  else
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      _detail,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
