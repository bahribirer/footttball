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
  String getCountry(String countryname){

    return countryCodes[countryname] ?? ""; 

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

  final Map<String, String> countryCodes = {
  "United States": "US",
  "England":"GB",
  "China": "CN",
  "Netherlands":"NL",
  "India": "IN",
  "Indonesia": "ID",
  "Pakistan": "PK",
  "Brazil": "BR",
  "Nigeria": "NG",
  "Bangladesh": "BD",
  "Russia": "RU",
  "Mexico": "MX",
  "Japan": "JP",
  "Ethiopia": "ET",
  "Philippines": "PH",
  "Egypt": "EG",
  "Vietnam": "VN",
  "DR Congo": "CD",
  "Turkey": "TR",
  "Iran": "IR",
  "Germany": "DE",
  "Thailand": "TH",
  "United Kingdom": "GB",
  "France": "FR",
  "Italy": "IT",
  "Tanzania": "TZ",
  "South Africa": "ZA",
  "Myanmar": "MM",
  "Kenya": "KE",
  "South Korea": "KR",
  "Colombia": "CO",
  "Spain": "ES",
  "Uganda": "UG",
  "Argentina": "AR",
  "Algeria": "DZ",
  "Sudan": "SD",
  "Ukraine": "UA",
  "Iraq": "IQ",
  "Afghanistan": "AF",
  "Poland": "PL",
  "Canada": "CA",
  "Morocco": "MA",
  "Saudi Arabia": "SA",
  "Uzbekistan": "UZ",
  "Peru": "PE",
  "Angola": "AO",
  "Malaysia": "MY",
  "Mozambique": "MZ",
  "Ghana": "GH",
  "Yemen": "YE",
  "Nepal": "NP",
  "Venezuela": "VE",
  "Belgium":"BE",
  "Cote d'Ivoire":"CI",
  "Uruguay":"UY",
  "Serbia":"RS",
  "Portugal":"PT",
  "Denmark":"DK",
  "Switzerland":"CH",
  "Cameroon":"CM",
  "Croatia":"HR",
  "Albania":"AL",
  "Ireland":"IE",
  "Austria":"AT",
  "Sweden":"SE",
  "Bosnia-Herzegovina":"BA",
  "Mali":"ML",
  "Senegal":"SN",
  "Kosovo":"XK"
};

}