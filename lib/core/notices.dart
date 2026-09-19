import 'package:flutter/material.dart';

import 'package:footttball/core/theme/app_theme.dart';

/// Yönetici duyuruları.
///
/// İki kaynak: oyun soketinden gelen anlık `admin_notice` olayı ve menü
/// açılışında okunan pano (`GET /api/v1/notice`). İkisi de aynı bantla
/// gösterilir. Aynı pano duyurusu bir kez gösterilir (id ile).
class Notices {
  Notices._();
  static final Notices instance = Notices._();

  /// Uygulama kökündeki navigator; overlay bunun üstüne çizilir.
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  int? _lastBoardId;
  OverlayEntry? _entry;
  BuildContext? _fallback;

  /// Kök navigator anahtarı takılı değilse (testler, gömülü kullanım)
  /// ekranlar kendi bağlamını verir; overlay oradan bulunur.
  void register(BuildContext context) => _fallback = context;

  /// Pano duyurusu: daha önce gösterilmediyse gösterir.
  void showBoard(Map<String, dynamic>? notice) {
    if (notice == null) return;
    final id = notice['id'] as int?;
    if (id != null && id == _lastBoardId) return;
    _lastBoardId = id;
    show(
      title: notice['title'] as String? ?? 'Duyuru',
      message: notice['message'] as String? ?? '',
    );
  }

  void show({required String title, required String message}) {
    var overlay = navigatorKey.currentState?.overlay;
    final fb = _fallback;
    if (overlay == null && fb != null && fb.mounted) {
      overlay = Overlay.maybeOf(fb, rootOverlay: true);
    }
    if (overlay == null || message.isEmpty) return;
    _entry?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _NoticeBanner(
        title: title,
        message: message,
        onClose: () {
          entry.remove();
          if (_entry == entry) _entry = null;
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

class _NoticeBanner extends StatefulWidget {
  const _NoticeBanner({
    required this.title,
    required this.message,
    required this.onClose,
  });

  final String title;
  final String message;
  final VoidCallback onClose;

  @override
  State<_NoticeBanner> createState() => _NoticeBannerState();
}

class _NoticeBannerState extends State<_NoticeBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();

  @override
  void initState() {
    super.initState();
    // Uzun mesaj daha uzun kalır; en az 6 sn.
    final secs = (6 + widget.message.length ~/ 25).clamp(6, 15);
    Future<void>.delayed(Duration(seconds: secs), _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _c.reverse();
    if (mounted) widget.onClose();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Positioned(
      top: top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
            .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
        child: Material(
          color: Colors.transparent,
          child: Dismissible(
            key: const ValueKey('notice_banner'),
            direction: DismissDirection.up,
            onDismissed: (_) => widget.onClose(),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceHigh,
                borderRadius: BorderRadius.circular(AppTheme.radius),
                border: Border.all(color: AppTheme.gold.withOpacity(0.55)),
                boxShadow: AppTheme.shadow,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.campaign_rounded,
                        color: AppTheme.gold, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            style: const TextStyle(
                              color: AppTheme.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              letterSpacing: 0.6,
                            )),
                        const SizedBox(height: 2),
                        Text(widget.message, style: AppTheme.body),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _dismiss,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded,
                        color: AppTheme.textMuted, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
