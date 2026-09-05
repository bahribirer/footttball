import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import 'package:footttball/core/config/app_config.dart';
import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/models/room_models.dart';

/// Sunucuyla oyun oturumu bağlantısı (protokol v2).
///
/// Tüm mesajlar JSON'dur ve `events` akışı üzerinden yayınlanır. Tiki Taka Toe
/// gibi oyun mantığı istemcide olan modlar `relay` ile haberleşir; sunucu
/// yönetimli modlar `action` gönderir.
class GameSocket {
  GameSocket._();
  static final GameSocket instance = GameSocket._();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeat;
  StreamController<SocketEvent> _events =
      StreamController<SocketEvent>.broadcast();

  /// Bu cihazın oda içindeki yeri: 0 = kurucu (X), 1 = katılan (O).
  int mySlot = 0;
  GameMode mode = GameMode.tikiTakaToe;
  String roomCode = '';
  List<RoomPlayer> players = const [];
  bool get isConnected => _channel != null;

  /// `start` ve son `state` yükleri saklanır; oyun ekranı geç açılsa bile
  /// (VS animasyonu sırasında) güncel durumu kaçırmaz.
  Map<String, dynamic> startPayload = const {};
  Map<String, dynamic> lastState = const {};

  Stream<SocketEvent> get events => _events.stream;

  String get mySymbol => mySlot == 0 ? 'X' : 'O';
  int get opponentSlot => 1 - mySlot;

  RoomPlayer? get me =>
      players.where((player) => player.slot == mySlot).firstOrNull;
  RoomPlayer? get opponent =>
      players.where((player) => player.slot != mySlot).firstOrNull;

  String get myName => me?.name ?? 'Sen';
  String get opponentName => opponent?.name ?? 'Rakip';

  // --- Tiki Taka Toe uyumluluk katmanı ---------------------------------
  // Mevcut oyun ekranı bu geri çağrıları kullanıyor; protokol değişse de
  // oyun mantığı olduğu gibi çalışmaya devam eder.
  bool playerTurn = false;
  String initialType = '';
  void Function(int index, String type, String? playerName)? makeMove;
  void Function()? onPlayerLeave;
  void Function(String name, String type)? onNameAnnounced;
  void Function(int seconds)? onTimerSync;
  void Function(int index)? onCellSelected;
  void Function(Map<String, dynamic> data)? onNextRoundData;
  void Function()? onReplayRequest;
  void Function()? onReplayDeclined;
  void Function(Map<String, dynamic> data)? onReplayData;

  // --- bağlantı ---------------------------------------------------------

  /// Odaya bağlanır. Zaten açık bir bağlantı varsa önce kapatılır.
  Future<void> connect({
    required String code,
    required String name,
    required GameMode mode,
  }) async {
    await disconnect();

    if (_events.isClosed) {
      _events = StreamController<SocketEvent>.broadcast();
    }

    this.mode = mode;
    roomCode = code;
    players = const [];
    startPayload = const {};
    lastState = const {};
    playerTurn = false;
    initialType = '';

    final uri = Uri.parse(
      '${AppConfig.wsBase}/ws/v2/$code'
      '?name=${Uri.encodeQueryComponent(name)}&mode=${mode.id}',
    );

    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    await channel.ready;

    _subscription = channel.stream.listen(
      _handleMessage,
      onError: (Object error) => _emit({'type': 'error', 'message': '$error'}),
      onDone: () => _emit({'type': 'closed'}),
      cancelOnError: false,
    );

    _heartbeat = Timer.periodic(
      AppConfig.heartbeatInterval,
      (_) => send({'type': 'ping'}),
    );
  }

  Future<void> disconnect() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close(ws_status.normalClosure);
    _channel = null;
  }

  /// Ekranlar arası geçişte geri çağrıların birbirine karışmasını önler.
  void clearCallbacks() {
    makeMove = null;
    onPlayerLeave = null;
    onNameAnnounced = null;
    onTimerSync = null;
    onCellSelected = null;
    onNextRoundData = null;
    onReplayRequest = null;
    onReplayDeclined = null;
    onReplayData = null;
  }

  // --- gönderim ---------------------------------------------------------

  void send(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode(message));
  }

  /// Sunucu yönetimli modlarda oyun hamlesi.
  void action(String action, {String? value, Map<String, dynamic>? extra}) {
    send({
      'type': 'action',
      'action': action,
      if (value != null) 'value': value,
      ...?extra,
    });
  }

  /// Oyun mantığı istemcide olan modlarda ham mesaj aktarımı.
  void relay(Map<String, dynamic> data) =>
      send({'type': 'relay', 'data': data});

  void requestRematch() => send({'type': 'rematch'});

  void leave() => send({'type': 'leave'});

  // --- alım -------------------------------------------------------------

  void _handleMessage(dynamic raw) {
    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(raw as String);
      if (decoded is! Map) return;
      message = decoded.cast<String, dynamic>();
    } on FormatException {
      return; // protokol dışı mesajları yok say
    }

    switch (message['type']) {
      case 'joined':
        final you = (message['you'] as Map?)?.cast<String, dynamic>();
        mySlot = you?['slot'] as int? ?? 0;
        initialType = mySymbol;
        playerTurn = mySlot == 0; // kurucu başlar
        final room = (message['room'] as Map?)?.cast<String, dynamic>();
        mode = GameMode.fromId(room?['mode'] as String?);
        _updatePlayers(room?['players']);
        break;

      case 'room':
        _updatePlayers(message['players']);
        break;

      case 'start':
        startPayload =
            (message['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
        lastState = startPayload;
        _updatePlayers(startPayload['players']);
        break;

      case 'state':
        lastState =
            (message['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
        break;

      case 'relay':
        _handleRelay(
          (message['data'] as Map?)?.cast<String, dynamic>() ?? {},
          message['from'] as int? ?? opponentSlot,
        );
        break;

      case 'event':
        _handleEvent(message);
        break;

      case 'opponent_left':
        onPlayerLeave?.call();
        break;

      case 'pong':
        return; // akışa taşımaya gerek yok
    }

    _emit(message);
  }

  void _updatePlayers(dynamic source) {
    if (source is! List) return;
    players = source
        .map((e) => RoomPlayer.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  void _handleEvent(Map<String, dynamic> message) {
    switch (message['event']) {
      case 'next_round':
      case 'rematch_data':
        onNextRoundData?.call(message);
        break;
    }
  }

  /// Tiki Taka Toe'nun istemci mesajlarını ilgili geri çağrıya dağıtır.
  ///
  /// Hamleler her iki oyuncuya da iletilir: tahtayı ve sıra devrini işleyen
  /// kod ortaktır. Buna karşılık seçim/ad/sayaç bildirimleri yalnızca
  /// rakipten geldiğinde işlenir; aksi halde oyuncu kendi seçtiği kutuyu
  /// "rakibin seçimi" olarak görüyordu.
  void _handleRelay(Map<String, dynamic> data, int fromSlot) {
    final type = data['type'] as String?;
    final symbol = data['symbol'] as String? ?? type;

    // Hamle, `index` ile birlikte bir oyuncu sembolü taşır. Yalnızca `index`
    // varlığına bakmak yetmiyor: kutu seçimi bildirimi de `index` taşıdığı
    // için hamle sanılıyor, seçilen kutu doluyor ve sıra devrediyordu.
    if (data.containsKey('index') && (symbol == 'X' || symbol == 'O')) {
      makeMove?.call(
        data['index'] as int,
        symbol!,
        data['playerName'] as String?,
      );
      return;
    }

    if (fromSlot == mySlot) return; // kendi bildirimimi yok say

    switch (type) {
      case 'announceName':
        onNameAnnounced?.call(
          data['name'] as String? ?? '',
          data['playerType'] as String? ?? '',
        );
        break;
      case 'timerSync':
        onTimerSync?.call(data['seconds'] as int? ?? 0);
        break;
      case 'selectCell':
        onCellSelected?.call(data['index'] as int? ?? -1);
        break;
      case 'deselectCell':
        onCellSelected?.call(-1);
        break;
      case 'replayRequest':
        onReplayRequest?.call();
        break;
      case 'replayDecline':
        onReplayDeclined?.call();
        break;
      case 'replayData':
        onReplayData?.call(data);
        break;
      case 'leaveRoom':
        onPlayerLeave?.call();
        break;
    }
  }

  void _emit(Map<String, dynamic> message) {
    if (_events.isClosed) return;
    _events.add(SocketEvent(message['type'] as String? ?? 'unknown', message));
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
