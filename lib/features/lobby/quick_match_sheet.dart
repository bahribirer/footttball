import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:footttball/core/config/app_config.dart';
import 'package:footttball/core/session.dart';
import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/features/lobby/waiting_room_screen.dart';
import 'package:footttball/shared/widgets/app_background.dart';

/// Hızlı eşleşme sayfası.
///
/// Oda kodu paylaşmak tek giriş yoluydu; oynamak için arkadaşının aynı anda
/// müsait olması gerekiyordu. Burada mod seçilip kuyruğa girilir, sunucu
/// aynı modu bekleyen biriyle eşleştirir.
///
/// Kuyrukta kalmak açık WebSocket'e bağlıdır: sayfa kapanınca bağlantı da
/// kapanır ve oyuncu kuyruktan düşer, hayalet eşleşme olmaz.
class QuickMatchSheet extends StatefulWidget {
  const QuickMatchSheet({super.key, required this.modes});

  final List<GameMode> modes;

  @override
  State<QuickMatchSheet> createState() => _QuickMatchSheetState();
}

class _QuickMatchSheetState extends State<QuickMatchSheet> {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  GameMode? _searching;
  String _status = '';
  int _waiting = 0;

  @override
  void dispose() {
    _leaveQueue();
    super.dispose();
  }

  void _leaveQueue() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  Future<void> _search(GameMode mode) async {
    _leaveQueue();
    setState(() {
      _searching = mode;
      _status = 'Rakip aranıyor...';
      _waiting = 0;
    });

    final uri = Uri.parse(
      '${AppConfig.wsBase}/ws/queue'
      '?name=${Uri.encodeComponent(Session.instance.displayName)}'
      '&mode=${mode.id}',
    );

    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _subscription = channel.stream.listen(
        _onMessage,
        onError: (_) => _fail('Bağlantı kurulamadı'),
        onDone: () {
          if (mounted && _searching != null) _fail('Bağlantı kapandı');
        },
      );
    } catch (_) {
      _fail('Bağlantı kurulamadı');
    }
  }

  void _onMessage(dynamic raw) {
    if (!mounted) return;
    Map<String, dynamic> message;
    try {
      message = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (message['event']) {
      case 'queued':
        setState(() => _status = 'Sıraya girdin, rakip bekleniyor...');
        break;

      case 'still_waiting':
        setState(() {
          _waiting = message['waiting'] as int? ?? 0;
          _status = 'Hâlâ arıyorum... biraz sürebilir';
        });
        break;

      case 'matched':
        final code = message['code'] as String?;
        final mode = _searching;
        _leaveQueue();
        if (code != null && mode != null && mounted) {
          Navigator.of(context).pop();
          Navigator.of(context).push(MaterialPageRoute(
            // Hızlı eşleşmede kurucu yok: odayı sunucu açıyor, iki taraf
            // da katılan gibi davranır.
            builder: (_) => WaitingRoomScreen(
              roomCode: code,
              mode: mode,
              isHost: false,
            ),
          ));
        }
        break;

      case 'queue_timeout':
        _fail('Şu an müsait rakip yok. Oda kurup arkadaşını çağırabilirsin.');
        break;
    }
  }

  void _fail(String message) {
    _leaveQueue();
    if (!mounted) return;
    setState(() {
      _searching = null;
      _status = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: NeonPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NeonTitle('HIZLI EŞLEŞ', fontSize: 20),
            const SizedBox(height: 6),
            Text(
              _searching == null ? 'Hangi modda oynamak istersin?' : _status,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 12.5),
            ),
            if (_waiting > 1) ...[
              const SizedBox(height: 4),
              Text(
                'Kuyrukta $_waiting kişi',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
            const SizedBox(height: 18),
            if (_searching != null)
              Column(
                children: [
                  const CircularProgressIndicator(color: Colors.cyanAccent),
                  const SizedBox(height: 18),
                  TextButton(
                    onPressed: () {
                      _leaveQueue();
                      setState(() {
                        _searching = null;
                        _status = '';
                      });
                    },
                    child: const Text('VAZGEÇ',
                        style: TextStyle(color: Colors.white54)),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  for (final mode in widget.modes)
                    ActionChip(
                      avatar: Icon(mode.icon, size: 16, color: Colors.white),
                      label: Text(mode.title),
                      labelStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      backgroundColor: mode.colors.first,
                      onPressed: () => _search(mode),
                    ),
                ],
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
