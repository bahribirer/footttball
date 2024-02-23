import 'package:http/retry.dart';

class getTeamInfo{

  static final getTeamInfo _instance = getTeamInfo._internal();

  // Private named constructor so that it cannot be instantiated outside the class.
  getTeamInfo._internal();

  // Factory constructor to return the same instance.
  factory getTeamInfo() {
    return _instance;
  }
  String getmap(String teamname){

    return teams[teamname] ?? ""; 

  }

  Map<String,String> teams={
    "Premier League":"GB1",
    "Ligue1":"FR1",
    "LaLiga":"ES1",
    "Bundesliga":"L1",
    "Super League":"TR1",
    "Serie A":"IT1",
    "Random":"RANDOM"
  };
}