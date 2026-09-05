import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:footttball/core/config/app_config.dart';
import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/models/team_model.dart';

/// Backend REST istemcisi.
class ApiService {
  static const String _base = AppConfig.apiBase;

  static Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_base$path').replace(queryParameters: query);

  static Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await http.get(uri).timeout(AppConfig.requestTimeout);
    if (response.statusCode != 200) {
      throw ApiException('İstek başarısız (${response.statusCode})', uri);
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  // --- Tiki Taka Toe tahtası -------------------------------------------

  /// Yeni tur / rövanş için tahta verisi.
  static Future<TeamModel> fetchGrid(String leagueId) async {
    final json = await _getJson(_uri('/api/v1/final_grid/$leagueId'));
    return TeamModel.fromJson(json);
  }

  /// Ağ hatasında oyunu kilitlememek için boş model döndüren güvenli sürüm.
  static Future<TeamModel> getLeagueInfo(String leagueId) async {
    try {
      return await fetchGrid(leagueId);
    } catch (_) {
      return TeamModel(nations: const [], clubs: const []);
    }
  }

  // --- Oyuncu ------------------------------------------------------------

  /// Tahminin millet + kulüp ikilisine uyup uymadığını sorar.
  static Future<bool> checkPlayer({
    required String playerName,
    required String nationality,
    required String club,
  }) async {
    final response = await http
        .post(
          _uri('/api/v1/guess_player/'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'player_name': playerName,
            'nationality': nationality,
            'club': club,
          }),
        )
        .timeout(AppConfig.requestTimeout);

    if (response.statusCode != 200) return false;
    return response.body.trim().toLowerCase() == 'true';
  }

  /// Otomatik tamamlama için oyuncu arar.
  static Future<List<Map<String, dynamic>>> searchPlayers(String query) async {
    if (query.trim().length < 2) return const [];

    final response = await http
        .get(_uri('/api/v1/get_player_names', {'name': query}))
        .timeout(AppConfig.requestTimeout);

    if (response.statusCode != 200) return const [];

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) return const [];
    return decoded.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  /// Kulüp logosunun görüntü adresi.
  static String logoUrl(String clubName) =>
      '$_base/api/v1/logo_image/${Uri.encodeComponent(clubName)}';

  // --- Oda ---------------------------------------------------------------

  /// Sunucudan benzersiz oda kodu ister; iki kurucunun aynı kodu almasını önler.
  static Future<RoomTicket> createRoom({
    required GameMode mode,
    String? leagueId,
    int? roundCount,
    int? clockSeconds,
    String? categoryId,
  }) async {
    final response = await http
        .post(
          _uri('/api/v1/rooms'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'mode': mode.id,
            if (leagueId != null) 'league_id': leagueId,
            if (roundCount != null) 'round_count': roundCount,
            if (clockSeconds != null) 'clock_seconds': clockSeconds,
            if (categoryId != null) 'category_id': categoryId,
          }),
        )
        .timeout(AppConfig.requestTimeout);

    if (response.statusCode != 200) {
      throw ApiException(
          'Oda oluşturulamadı (${response.statusCode})', _uri('/api/v1/rooms'));
    }

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return RoomTicket(
      code: json['code'] as String,
      mode: GameMode.fromId(json['mode'] as String?),
    );
  }

  /// Kurucu lig/tur seçimini tamamladığında oda ayarlarını sunucuya işler.
  ///
  /// Oda kodu seçimden önce üretilip ekranda gösterildiği için ayarlar bu
  /// çağrıyla güncellenir.
  static Future<void> updateRoom({
    required String code,
    required GameMode mode,
    String? leagueId,
    int? roundCount,
    int? clockSeconds,
    String? categoryId,
  }) async {
    final response = await http
        .patch(
          _uri('/api/v1/rooms/$code'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'mode': mode.id,
            if (leagueId != null) 'league_id': leagueId,
            if (roundCount != null) 'round_count': roundCount,
            if (clockSeconds != null) 'clock_seconds': clockSeconds,
            if (categoryId != null) 'category_id': categoryId,
          }),
        )
        .timeout(AppConfig.requestTimeout);

    if (response.statusCode != 200) {
      throw ApiException(
        'Oda ayarları güncellenemedi (${response.statusCode})',
        _uri('/api/v1/rooms/$code'),
      );
    }
  }

  /// Odanın var olup olmadığını ve katılıma açık olup olmadığını sorar.
  static Future<RoomStatus> roomStatus(String code) async {
    final json = await _getJson(_uri('/api/v1/rooms/$code'));
    return RoomStatus(
      exists: json['room_exists'] as bool? ?? false,
      joinable: json['is_joinable'] as bool? ?? false,
      mode:
          json['mode'] != null ? GameMode.fromId(json['mode'] as String) : null,
      players: json['players'] as int? ?? 0,
    );
  }

  // --- Kategoriler --------------------------------------------------------

  static Future<List<GameCategory>> categories({int count = 3}) async {
    final response = await http
        .get(_uri('/api/v1/categories', {'count': '$count'}))
        .timeout(AppConfig.requestTimeout);

    if (response.statusCode != 200) return const [];

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) return const [];
    return decoded
        .map((e) => GameCategory(
              id: (e as Map)['id'] as String,
              label: e['label'] as String,
            ))
        .toList();
  }
}

class RoomTicket {
  final String code;
  final GameMode mode;

  const RoomTicket({required this.code, required this.mode});
}

class RoomStatus {
  final bool exists;
  final bool joinable;
  final GameMode? mode;
  final int players;

  const RoomStatus({
    required this.exists,
    required this.joinable,
    required this.players,
    this.mode,
  });
}

class GameCategory {
  final String id;
  final String label;

  const GameCategory({required this.id, required this.label});
}

class ApiException implements Exception {
  final String message;
  final Uri uri;

  const ApiException(this.message, this.uri);

  @override
  String toString() => 'ApiException: $message ($uri)';
}
