import 'package:flutter/material.dart';

class Constants {
  Constants._privateConstructor();
  static final Constants _instance = Constants._privateConstructor();

  factory Constants() {
    return _instance;
  }

  Color titleColor = Color(0xFFE25E3E);
  Color buttonColor = Color(0xFFE25E3E);
  Color textColor = Color(0xFFFFFFFF);
  Color fadeTextColor = Color.fromARGB(255, 87, 87, 87);
  Color blackTextColor = Color.fromARGB(255, 51, 51, 51);

  // Temp
  Color primaryColor = Color(0xFFFFFFFF);
  Color secondaryColor = Color(0xFF000000);
  Color errorColor = Color(0xFFDC143C);
  Color backgroundColor = Color(0xFFE1E5EE);

  Color tempColor = Color(0xFFFFB319);

  Color deepBlue = Color(0xFF007BA7);
  Color lightBlue = Color(0xFF4F80E2);
  Color teal = Color(0xFF15CDCA);
  Color green = Color(0xFF4FE0B6);
  Color lightGray = Color(0xFF92B8FF);
  Color darkBlue2 = Color(0xFF003B8E);
  Color darkBlue = Color(0xFF1564BF);
  Color darkBlue3 = Color(0xFF1E2A55);

  Color mayaBlue = Color(0xFF73C2FB);
  Color persianBlue = Color(0xFF1C39BB);
  Color mediumGray = Color(0xFF5A6D8C);
  Color lightBlueGray = Color(0xFF8A9CB2);
  Color mainBlue = Color(0xFF007BA7);
  Color mainBlueDarkShade = Color(0XFF004063);
  Color mainBlueDarkShade1 = Color(0XFF004F74);
  Color mainBlueDarkShade2 = Color(0xFF005E85);
  Color mainBlueDarkShade3 = Color(0XFF006D96);
  Color mainBlueLightShade1 = Color(0xFF66A7B9);

  // Gradients
  LinearGradient deepBlueToLightBlue = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3E54D3), Color(0xFF4F80E2)],
  );

  LinearGradient blueDarkBlue = LinearGradient(
    begin: Alignment.bottomRight,
    end: Alignment.topLeft,
    colors: [
      Color.fromARGB(255, 0, 85, 122),
      Color.fromARGB(255, 11, 167, 224)
    ],
  );
  LinearGradient blueDarkBlueOpacity = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.fromARGB(255, 7, 106, 149).withOpacity(0.1),
      Color.fromARGB(255, 11, 167, 224).withOpacity(0.1)
    ],
  );

  LinearGradient deepBlueToLightBlueOpacity = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF3E54D3).withOpacity(0.1),
      Color(0xFF4F80E2).withOpacity(0.1)
    ],
  );

  LinearGradient lightBlueToTeal = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4F80E2), Color(0xFF15CDCA)],
  );

  LinearGradient tealToGreen = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF15CDCA), Color(0xFF4FE0B6)],
  );

  //--------------------
  LinearGradient blueToLightBlue = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F52BA), Color(0xFF73C2FB)],
  );

  LinearGradient sapphireToAzure = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F52BA), Color(0xFF007FFF)],
  );

  LinearGradient ceruleanToCapri = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2A52BE), Color(0xFF00BFFF)],
  );

  LinearGradient persianToMaya = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1C39BB), Color(0xFF73C2FB)],
  );

  LinearGradient denimToPacific = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1560BD), Color(0xFF1CA9C9)],
  );
}
