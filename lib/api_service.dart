import 'dart:convert';
import 'players.dart';
import 'players.dart';
import 'package:http/http.dart' as http;

class ApiService {
  final String baseUrl;

  ApiService(this.baseUrl);

  Future<Map<String, dynamic>> getFinalGrid(String leagueId) async {
    final response = await http.get(Uri.parse('$baseUrl/api/v1/final_grid/$leagueId'));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load final grid information');
    }
  }

  Future<bool> makePlayerGuess(String playerName, String nationality, String club) async {
  final response = await http.get(Uri.parse('$baseUrl/api/v1/make_player_guess/$playerName/$nationality/$club'));

  if (response.statusCode == 200) {
    return response.body.toLowerCase() == 'true';
  } else {
    throw Exception('Failed to make player guess');
  }
}

  Future<List> getPlayersByLeague(String leagueId) async {
  final response = await http.get(Uri.parse('$baseUrl/api/v1/players_by_league/$leagueId'));

  if (response.statusCode == 200) {
    final List<Map<String, dynamic>> playerDataList = List<Map<String, dynamic>>.from(json.decode(response.body));
    final List players = playerDataList.map((playerData) => Player.fromJson(playerData)).toList();
    return players;
  } else {
    throw Exception('Failed to load players by league');
  }
}


Future<String> getClubLogo(String leagueId, String clubName) async {
  final response = await http.get(Uri.parse('$baseUrl/api/v1/club_logo/$leagueId/$clubName'));

  if (response.statusCode == 200) {
    return response.body;
  } else {
    throw Exception('Failed to load club logo');
  }
}
Future<String> getLeagueInfo(String gameMode) async {
  final response = await http.get(Uri.parse('$baseUrl/api/v1/league_info/$gameMode'));

  if (response.statusCode == 200) {
    return response.body;
  } else {
    throw Exception('Failed to load league information');
  }

  
}

Future<Map<String, dynamic>> getPlayersAndCountriesByLeague(String leagueId) async {
    try {
      // Oyuncu ve ülke bilgilerini alma
      final response = await http.get(Uri.parse('$baseUrl/api/v1/players_and_countries_by_league/$leagueId'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        final List<Map<String, dynamic>> playerDataList = List<Map<String, dynamic>>.from(data['players']);
        final List players = playerDataList.map((playerData) => Player.fromJson(playerData)).toList();

        final List<String> countries = List<String>.from(data['countries']);

        return {'players': players, 'countries': countries};
      } else {
        throw Exception('Failed to load players and countries by league');
      }
    } catch (e) {
      throw Exception('Error: $e');
    }
  }
}









