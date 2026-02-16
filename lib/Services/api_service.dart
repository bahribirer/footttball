import 'dart:convert';
import 'dart:io';
import 'package:footttball/Models/teamModel.dart';
import '../Models/players.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static final String baseUrl = "https://tikitakatoe.com";

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
    print("DEBUG: Fetching league info for: $gameMode");
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/api/v1/final_grid/$gameMode"),
      ).timeout(Duration(seconds: 15));

      if (response.statusCode == 200) {
        String decodedBody = utf8.decode(response.bodyBytes);
        Map<String, dynamic> jsonMap = json.decode(decodedBody);
        return TeamModel.fromJson(jsonMap);
      }
      return TeamModel(nations: [""], clubs: [""]);
    } catch (e) {
      print("DEBUG: getLeagueInfo error: $e");
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
      final response = await http.get(Uri.parse(
          '$baseUrl/api/v1/club_logo/$gamemode/${Uri.encodeComponent(countryname)}'));

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

  Future<List<Map<String, dynamic>>> getPlayerNames({required String query}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/get_player_names?name=$query'),
      ).timeout(Duration(seconds: 15));
      print('Response: ${response.body}'); // Yanıtı konsola yazdır

      if (response.statusCode == 200) {
        // Backend returns a flat list of player maps
        final data = json.decode(utf8.decode(response.bodyBytes));
        final List<dynamic> players = data is List ? data : data['player_names'];
        // Convert to List<Map<String, dynamic>>
        return players.map((e) => e as Map<String, dynamic>).toList();
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

  static Future<Map<String, dynamic>> checkRoom(String roomId) async {
    final url = '$baseUrl/check_room/$roomId';
    print("DEBUG: checkRoom request to: $url");
    try {
      final response = await http.get(
        Uri.parse(url),
      ).timeout(Duration(seconds: 15));
      
      print("DEBUG: checkRoom response status: ${response.statusCode}");
      print("DEBUG: checkRoom response body: ${response.body}");

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Server Error: ${response.statusCode}');
      }
    } catch (e) {
      print("DEBUG: checkRoom ERROR for room $roomId: $e");
      if (e is SocketException) {
        print("CRITICAL: Network issue! Ensure device is on $baseUrl network and Firewall is off.");
      }
      rethrow;
    }
  }
}
