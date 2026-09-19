import 'dart:async';

import 'package:flutter/material.dart';

import 'package:footttball/core/session.dart';
import 'package:footttball/data/services/api_service.dart';
import 'package:footttball/shared/widgets/game_dialogs.dart';

/// Can durumu (sunucudan): cihaz başına saatte 10 maç.
class LivesStatus {
  const LivesStatus({
    required this.lives,
    required this.max,
    required this.resetsAt,
  });

  factory LivesStatus.fromJson(Map<String, dynamic> json) => LivesStatus(
        lives: json['lives'] as int? ?? 0,
        max: json['max'] as int? ?? 10,
        resetsAt: DateTime.fromMillisecondsSinceEpoch(
          (((json['resets_at'] as num?) ?? 0) * 1000).round(),
        ),
      );

  final int lives;
  final int max;
  final DateTime resetsAt;

  Duration get resetsIn {
    final d = resetsAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  String get resetsInText {
    final m = resetsIn.inMinutes;
    if (m >= 60) return '${resetsIn.inHours} sa ${m % 60} dk';
    if (m >= 1) return '$m dk';
    return '${resetsIn.inSeconds} sn';
  }
}

/// Can önbelleği ve giriş kapısı.
///
/// Sunucu zaten canı olmayanı odaya almaz; burası oyuncuya daha erken ve
/// daha nazik söyler. Ağ hatasında engel olmaz — kapı sunucudadır.
class Lives {
  Lives._();
  static final Lives instance = Lives._();

  final ValueNotifier<LivesStatus?> status = ValueNotifier<LivesStatus?>(null);

  Future<LivesStatus?> refresh() async {
    final id = Session.instance.playerId;
    if (id.isEmpty) return null;
    final s = await ApiService.lives(id);
    if (s != null) status.value = s;
    return s;
  }

  /// Oyuna girmeden önce: can varsa true. Yoksa uyarı gösterir, false döner.
  Future<bool> ensure(BuildContext context) async {
    final s = await refresh();
    if (s == null || s.lives > 0) return true;
    if (!context.mounted) return false;
    GameDialogs.showWarning(
      context,
      title: 'CANIN BİTTİ',
      message: 'Bu saatlik hakkın doldu. ${s.resetsInText} sonra '
          '${s.max} canın yenilenecek.',
    );
    return false;
  }
}
