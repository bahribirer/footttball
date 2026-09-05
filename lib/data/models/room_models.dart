/// Sunucudan gelen oda ve oyun durumu modelleri.

class RoomPlayer {
  final int slot;
  final String name;
  final String symbol;
  final int score;
  final bool connected;

  const RoomPlayer({
    required this.slot,
    required this.name,
    required this.symbol,
    required this.score,
    required this.connected,
  });

  factory RoomPlayer.fromJson(Map<String, dynamic> json) => RoomPlayer(
        slot: json['slot'] as int? ?? 0,
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? json['name'] as String
            : 'Oyuncu ${(json['slot'] as int? ?? 0) + 1}',
        symbol: json['symbol'] as String? ?? 'X',
        score: json['score'] as int? ?? 0,
        connected: json['connected'] as bool? ?? true,
      );
}

/// Sunucudan gelen her mesaj bu tipe sarılarak yayınlanır.
class SocketEvent {
  final String type;
  final Map<String, dynamic> raw;

  const SocketEvent(this.type, this.raw);

  /// `event` alanı olan mesajlarda olay adı (`accepted`, `rejected`, ...).
  String? get event => raw['event'] as String?;

  Map<String, dynamic> get payload =>
      (raw['payload'] as Map?)?.cast<String, dynamic>() ?? const {};

  Map<String, dynamic> get data =>
      (raw['data'] as Map?)?.cast<String, dynamic>() ?? const {};

  T? value<T>(String key) => raw[key] as T?;
}

/// Süre tabanlı modlarda (Son Harf, Kategori Yarışı) ortak durum.
class ClockGameState {
  final String phase;
  final int currentTurn;
  final Map<int, double> clocks;
  final int penalty;
  final List<HistoryEntry> history;
  final Map<int, int> scores;
  final String? requiredLetter;
  final String? lastAnswer;
  final String? categoryLabel;
  final List<String> examples;

  const ClockGameState({
    required this.phase,
    required this.currentTurn,
    required this.clocks,
    required this.penalty,
    required this.history,
    required this.scores,
    this.requiredLetter,
    this.lastAnswer,
    this.categoryLabel,
    this.examples = const [],
  });

  factory ClockGameState.fromJson(Map<String, dynamic> json) {
    final category = (json['category'] as Map?)?.cast<String, dynamic>();
    return ClockGameState(
      phase: json['phase'] as String? ?? 'idle',
      currentTurn: json['current_turn'] as int? ?? 0,
      clocks: _intDoubleMap(json['clocks']),
      penalty: json['penalty'] as int? ?? 3,
      history: ((json['history'] as List?) ?? const [])
          .map((e) => HistoryEntry.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      scores: _intIntMap(json['scores']),
      requiredLetter: json['required_letter'] as String?,
      lastAnswer: json['last_answer'] as String?,
      categoryLabel: category?['label'] as String?,
      examples: ((json['examples'] as List?) ?? const []).cast<String>(),
    );
  }

  static const ClockGameState empty = ClockGameState(
    phase: 'idle',
    currentTurn: 0,
    clocks: {},
    penalty: 3,
    history: [],
    scores: {},
  );

  double clockOf(int slot) => clocks[slot] ?? 0;
}

class HistoryEntry {
  final int slot;
  final String answer;
  final String? imageUrl;
  final String? club;
  final String? country;

  const HistoryEntry({
    required this.slot,
    required this.answer,
    this.imageUrl,
    this.club,
    this.country,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        slot: json['slot'] as int? ?? 0,
        answer: json['answer'] as String? ?? '',
        imageUrl: json['image_url'] as String?,
        club: json['club'] as String?,
        country: json['country'] as String?,
      );
}

/// Oyuncu Tahmin modunun tur durumu.
class DuelState {
  final String phase;
  final int round;
  final int totalRounds;
  final int countdown;
  final List<String> nations;
  final List<String> clubs;
  final int nationPicker;
  final int clubPicker;
  final String? selectedNation;
  final String? selectedClub;
  final Map<int, int> attempts;
  final int? roundWinner;
  final String? solution;
  final String? solutionImage;
  final Map<int, int> scores;

  const DuelState({
    required this.phase,
    required this.round,
    required this.totalRounds,
    required this.countdown,
    required this.nations,
    required this.clubs,
    required this.nationPicker,
    required this.clubPicker,
    required this.attempts,
    required this.scores,
    this.selectedNation,
    this.selectedClub,
    this.roundWinner,
    this.solution,
    this.solutionImage,
  });

  factory DuelState.fromJson(Map<String, dynamic> json) => DuelState(
        phase: json['phase'] as String? ?? 'idle',
        round: json['round'] as int? ?? 0,
        totalRounds: json['total_rounds'] as int? ?? 1,
        countdown: json['countdown'] as int? ?? 0,
        nations: ((json['nations'] as List?) ?? const []).cast<String>(),
        clubs: ((json['clubs'] as List?) ?? const []).cast<String>(),
        nationPicker: json['nation_picker'] as int? ?? 0,
        clubPicker: json['club_picker'] as int? ?? 1,
        selectedNation: json['selected_nation'] as String?,
        selectedClub: json['selected_club'] as String?,
        attempts: _intIntMap(json['attempts']),
        roundWinner: json['round_winner'] as int?,
        solution: json['solution'] as String?,
        solutionImage: json['solution_image'] as String?,
        scores: _intIntMap(json['scores']),
      );

  static const DuelState empty = DuelState(
    phase: 'idle',
    round: 0,
    totalRounds: 1,
    countdown: 0,
    nations: [],
    clubs: [],
    nationPicker: 0,
    clubPicker: 1,
    attempts: {},
    scores: {},
  );

  int attemptsOf(int slot) => attempts[slot] ?? 0;
  int scoreOf(int slot) => scores[slot] ?? 0;
}

// JSON'da sözlük anahtarları metne dönüştüğü için int'e geri çevrilir.
Map<int, double> _intDoubleMap(dynamic source) {
  final map = <int, double>{};
  if (source is Map) {
    source.forEach((key, value) {
      final slot = key is int ? key : int.tryParse('$key');
      if (slot != null && value is num) map[slot] = value.toDouble();
    });
  }
  return map;
}

Map<int, int> _intIntMap(dynamic source) {
  final map = <int, int>{};
  if (source is Map) {
    source.forEach((key, value) {
      final slot = key is int ? key : int.tryParse('$key');
      if (slot != null && value is num) map[slot] = value.toInt();
    });
  }
  return map;
}
