import 'package:flutter/material.dart';

import 'package:footttball/core/session.dart';
import 'package:footttball/features/lobby/create_room_screen.dart';
import 'package:footttball/features/lobby/join_room_screen.dart';
import 'package:footttball/shared/widgets/app_background.dart';

/// Seçilen mod için oda kur / odaya katıl ekranı.
class StartPage extends StatelessWidget {
  const StartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final mode = Session.instance.selectedMode;

    return Scaffold(
      body: Stack(
        children: [
          PlainBackground(accent: mode.colors.first),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: GlassBackButton(
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ),
          ),

          // Seçili mod rozeti
          Positioned(
            top: size.height * 0.30,
            left: 24,
            right: 24,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      mode.colors.first.withOpacity(0.75),
                      mode.colors.last.withOpacity(0.75),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withOpacity(0.25)),
                  boxShadow: [
                    BoxShadow(
                      color: mode.colors.first.withOpacity(0.4),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(mode.icon, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      mode.title.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Oda kur
          Positioned(
            right: size.width * 0.55,
            bottom: size.height * 0.05,
            child: GestureDetector(
              key: const ValueKey('btn_create_room'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreateRoomScreen()),
              ),
              child: Image.asset(
                'images/create.PNG',
                width: size.width * 0.4,
                height: size.height * 0.2,
                fit: BoxFit.contain,
              ),
            ),
          ),

          // Odaya katıl
          Positioned(
            left: size.width * 0.55,
            bottom: size.height * 0.05,
            child: GestureDetector(
              key: const ValueKey('btn_join_room'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const JoinRoomScreen()),
              ),
              child: Image.asset(
                'images/join.PNG',
                width: size.width * 0.4,
                height: size.height * 0.2,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
