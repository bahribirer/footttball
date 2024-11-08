import 'dart:convert';
import 'package:footttball/Models/teamModel.dart';
import '../Models/players.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static final String baseUrl = "http://192.168.0.27:8000";

  Future<bool> makePlayerGuess(
      String playerName, String nationality, String club) async {
    final response = await http.get(Uri.parse(
        '$baseUrl/api/v1/make_player_guess/$playerName/$nationality/$club'));

    if (response.statusCode == 200) {
      return response.body.toLowerCase() == 'true';
    } else {
      throw Exception('Failed to make player guess');
    }
  }

  static Future<Map<String, List<String>>> fetchReplayData(
      String leagueId) async {
    final response =
        await http.get(Uri.parse('$baseUrl/api/v1/replay_data/$leagueId'));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      List<String> nations = List<String>.from(data['nations']);
      List<String> clubs = List<String>.from(data['clubs']);
      return {"nations": nations, "clubs": clubs};
    } else {
      throw Exception("Failed to load replay data");
    }
  }

  Future<List<Player>> getPlayersByLeague(String leagueId) async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/v1/players_by_league/$leagueId'));

    if (response.statusCode == 200) {
      final List<Map<String, dynamic>> playerDataList =
          List<Map<String, dynamic>>.from(json.decode(response.body));
      final List<Player> players = playerDataList
          .map((playerData) => Player.fromJson(playerData))
          .toList();
      return players;
    } else {
      throw Exception('Failed to load players by league');
    }
  }

  Future<String> getClubLogo(String leagueId, String clubName) async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/v1/club_logo/$leagueId/$clubName'));

    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw Exception('Failed to load club logo');
    }
  }

  static Future<TeamModel?> getLeagueInfo(String gameMode) async {
    final response =
        await http.get(Uri.parse("$baseUrl/api/v1/final_grid/$gameMode"));

    try {
      if (response.statusCode == 200) {
        String decodedBody = utf8.decode(response.bodyBytes);
        Map<String, dynamic> jsonMap = json.decode(decodedBody);
        return TeamModel.fromJson(jsonMap);
      }
    } catch (e) {
      print(e);
      return TeamModel(nations: [""], clubs: [""]);
    }
  }

  Future<Map<String, dynamic>> getPlayersAndCountriesByLeague(
      String leagueId) async {
    try {
      final response = await http.get(Uri.parse(
          '$baseUrl/api/v1/players_and_countries_by_league/$leagueId'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        final List<Map<String, dynamic>> playerDataList =
            List<Map<String, dynamic>>.from(data['players']);
        final List<Player> players = playerDataList
            .map((playerData) => Player.fromJson(playerData))
            .toList();

        final List<String> countries = List<String>.from(data['countries']);

        return {'players': players, 'countries': countries};
      } else {
        throw Exception('Failed to load players and countries by league');
      }
    } catch (e) {
      throw Exception('Error: $e');
    }
  }

  static Future<String> getLogo(
      {required String gamemode, required String countryname}) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/v1/club_logo/$gamemode/$countryname'));

      if (response.statusCode == 200) {
        String decodedBody = utf8.decode(response.bodyBytes);
        Map<String, dynamic> jsonMap = json.decode(decodedBody);
        return jsonMap["logoURL"];
      } else {
        return "";
      }
    } catch (e) {
      print(e);
      return "";
    }
  }

  static Future<String> checkPlayer(
      {required String player_name,
      required String nationality,
      required String club}) async {
    final body = {
      "player_name": player_name,
      "nationality": nationality,
      "club": club
    };

    final headers = {
      'Content-Type': 'application/json',
    };

    final response = await http.post(Uri.parse('$baseUrl/api/v1/guess_player/'),
        body: jsonEncode(body), headers: headers);

    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw Exception('Failed to load league information');
    }
  }

  Future<List<String>> getPlayerNames({required String query}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/player_names?query=$query'),
      );
      print('Response: ${response.body}'); // Yanıtı konsola yazdır

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final names = List<String>.from(data['player_names']);
        print('Parsed Names: $names');
        return names;
      } else {
        print(
            'Failed to load player names with status: ${response.statusCode}');
        throw Exception('Failed to load player names');
      }
    } catch (e) {
      print('Error fetching player names: $e');
      rethrow;
    }
  }
}
