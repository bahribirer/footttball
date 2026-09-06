class TeamModel {
  List<String> nations;
  List<String> clubs;

  TeamModel({
    required this.nations,
    required this.clubs,
  });

  factory TeamModel.fromJson(Map<String, dynamic> json) => TeamModel(
        nations: List<String>.from(json["nations"].map((x) => x)),
        clubs: List<String>.from(json["clubs"].map((x) => x)),
      );

  Map<String, dynamic> toJson() => {
        "nations": List<dynamic>.from(nations.map((x) => x)),
        "clubs": List<dynamic>.from(clubs.map((x) => x)),
      };
}
