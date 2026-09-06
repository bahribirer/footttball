import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:footttball/data/services/api_service.dart';
import 'package:footttball/shared/widgets/app_background.dart';
import 'package:footttball/shared/widgets/player_search_dialog.dart';

/// Oyun boyunca kullanılan ortak diyaloglar.
class GameDialogs {
  const GameDialogs._();

  /// Son seçilen oyuncu adı — hamle mesajında karşı tarafa gönderilir.
  static String lastPickedPlayer = '';

  /// Tiki Taka Toe hücresi için oyuncu seçtirir ve tahmini doğrular.
  ///
  /// Dönüş: `true` doğru, `false` yanlış, `null` vazgeçildi (sıra korunur).
  static Future<bool?> pickPlayer(
    BuildContext context, {
    required String club,
    required String nationality,
  }) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => PlayerSearchDialog(nationality: nationality, club: club),
    );

    if (selected == null || selected.isEmpty) return null;

    lastPickedPlayer = selected;
    return ApiService.checkPlayer(
      playerName: selected,
      nationality: nationality,
      club: club,
    );
  }

  /// Tur/seri sonucu gibi bilgilendirme kutusu.
  static void showInfo(
    BuildContext context, {
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onDismiss,
  }) {
    final isSeries = title.contains('SERİ') || title.contains('SERIES');
    final isDraw = title.contains('BERABERE');

    _show(
      context,
      emoji: isSeries ? '🏆' : (isDraw ? '🤝' : '⚽'),
      title: title,
      message: message,
      actionLabel: actionLabel ?? (isSeries ? '🎮  YENİ OYUN' : '▶  DEVAM'),
      gradient: isSeries
          ? const [Color(0xFF6A11CB), Color(0xFF2575FC)]
          : (isDraw
              ? const [Color(0xFF232526), Color(0xFF414345)]
              : const [Color(0xFF0F2027), Color(0xFF2C5364)]),
      onDismiss: onDismiss,
    );
  }

  /// Eksik seçim gibi durumlarda uyarı kutusu.
  static void showWarning(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    _show(
      context,
      emoji: '⚠️',
      title: title,
      message: message,
      actionLabel: 'TAMAM',
      gradient: const [Color(0xFF3A1C1C), Color(0xFF5A2A2A)],
      accent: Colors.redAccent,
    );
  }

  /// Rakip oyundan ayrıldığında gösterilir; kapatınca geri çağrı çalışır.
  static void showDisconnected(BuildContext context,
      {required VoidCallback onExit}) {
    _show(
      context,
      emoji: '💔',
      title: 'BAĞLANTI KOPTU',
      message: 'Rakibin oyundan ayrıldı.',
      actionLabel: '🏠  MENÜYE DÖN',
      gradient: const [Color(0xFF1A1A2E), Color(0xFF16213E)],
      accent: Colors.redAccent,
      barrierDismissible: false,
      onDismiss: onExit,
    );
  }

  static void _show(
    BuildContext context, {
    required String emoji,
    required String title,
    required String message,
    required String actionLabel,
    required List<Color> gradient,
    Color accent = Colors.cyanAccent,
    bool barrierDismissible = true,
    VoidCallback? onDismiss,
  }) {
    showGeneralDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: title,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (dialogContext, _, __) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 30),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accent.withOpacity(0.4), width: 2),
            boxShadow: [
              BoxShadow(
                  color: accent.withOpacity(0.3),
                  blurRadius: 30,
                  spreadRadius: 2),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 24),
                Text(emoji, style: const TextStyle(fontSize: 46)),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                    shadows: [
                      Shadow(blurRadius: 12, color: accent.withOpacity(0.5))
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.88),
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: GestureDetector(
                    onTap: () => Navigator.of(dialogContext).pop(),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.amberAccent, Colors.orangeAccent],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          actionLabel,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
      transitionBuilder: (_, animation, __, child) => BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 6 * animation.value,
          sigmaY: 6 * animation.value,
        ),
        child: ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          child: FadeTransition(opacity: animation, child: child),
        ),
      ),
    ).then((_) => onDismiss?.call());
  }
}

/// Rakibin rövanş isteğini onaylama kutusu.
class RematchRequestDialog extends StatelessWidget {
  const RematchRequestDialog({
    super.key,
    required this.onAccept,
    required this.onDecline,
  });

  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: NeonPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔁', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 10),
            const NeonTitle('RÖVANŞ İSTEĞİ', fontSize: 20),
            const SizedBox(height: 14),
            const Text(
              'Rakibin yeniden oynamak istiyor.\nMeydan okumayı kabul ediyor musun?',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: onDecline,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 12),
                    backgroundColor: Colors.white12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'REDDET',
                    style: TextStyle(
                        color: Colors.white60, fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 14),
                    backgroundColor: const Color(0xFF2575FC),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 6,
                  ),
                  child: const Text(
                    'KABUL ET',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Rakip turu atlamayı teklif ettiğinde açılan onay penceresi.
///
/// Rövanş isteğiyle aynı akış: bir taraf gönderir, diğer taraf kabul eder ya
/// da reddeder. Kimsenin bilemediği turlarda sayacın dolmasını beklemeyi
/// gereksiz kılar.
class PassRequestDialog extends StatelessWidget {
  const PassRequestDialog({
    super.key,
    required this.onAccept,
    required this.onDecline,
  });

  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: NeonPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⏭️', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 10),
            const NeonTitle('PAS TEKLİFİ', fontSize: 20),
            const SizedBox(height: 14),
            const Text(
              'Rakibin bu turu pas geçmek istiyor.\n'
              'Kabul edersen tur puansız kapanır.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: onDecline,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 12),
                    backgroundColor: Colors.white12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'DEVAM ET',
                    style: TextStyle(
                        color: Colors.white60, fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 14),
                    backgroundColor: const Color(0xFF2575FC),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 6,
                  ),
                  child: const Text(
                    'PAS GEÇ',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
