import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:footttball/Helper/constants.dart';

class Helper {
  Helper._privateConstructor();
  static final Helper _instance = Helper._privateConstructor();

  factory Helper() {
    return _instance;
  }

  double getDeviceWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  double getDeviceHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }


  void showInfoDialog(BuildContext context, String title, String body) {
    showGeneralDialog(
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black38,
      transitionDuration: Duration(milliseconds: 500),
      pageBuilder: (ctx, anim1, anim2) =>
          StatefulBuilder(builder: (context, setState) {
        return Container(
          height: Helper().getDeviceHeight(context) / 4,
          child: AlertDialog(
            backgroundColor: Constants().textColor,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16.0))),
            title: Text(
              title,
              style: TextStyle(color: Constants().blackTextColor),
            ),
            content: Text(body,
                style:
                    TextStyle(color: Constants().blackTextColor, fontSize: 15)),
            elevation: 2,
          ),
        );
      }),
      transitionBuilder: (ctx, anim1, anim2, child) => BackdropFilter(
        filter:
            ImageFilter.blur(sigmaX: 4 * anim1.value, sigmaY: 4 * anim1.value),
        child: FadeTransition(
          child: child,
          opacity: anim1,
        ),
      ),
      context: context,
    );
  }
}