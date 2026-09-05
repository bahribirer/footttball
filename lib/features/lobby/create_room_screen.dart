import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:footttball/core/session.dart';
import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/services/api_service.dart';
import 'package:footttball/data/services/league_catalog.dart';
import 'package:footttball/features/lobby/waiting_room_screen.dart';
import 'package:footttball/shared/widgets/app_background.dart';
import 'package:footttball/shared/widgets/game_dialogs.dart';

/// Oda kurma ekranı. Oda kodunu sunucu üretir; iki kurucunun aynı kodu
/// almasından kaynaklanan çakışma böylece ortadan kalkar.
///
/// Kurucu, moda göre değişen ayarları burada seçer: lig (Tiki Taka Toe),
/// tur sayısı (Tiki Taka Toe + Oyuncu Tahmin), süre ve kategori (saatli
/// modlar). Seçimler bekleme odasına geçmeden önce `PATCH /rooms/{code}`
/// ile odaya işlenir.
class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen>
    with SingleTickerProviderStateMixin {
  static const _leagueAssets = {
    'Premier League': 'images/eng.PNG',
    'Ligue1': 'images/fran.PNG',
    'LaLiga': 'images/isp.PNG',
    'Bundesliga': 'images/ger.PNG',
    'Super League': 'images/tr.PNG',
    'Serie A': 'images/seri.PNG',
  };

  /// Kategori Yarışı'nda kurucuya sunulan seçenek sayısı.
  static const _categoryChoices = 5;

  final _catalog = LeagueCatalog();
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  GameMode get _mode => Session.instance.selectedMode;

  String _selectedLeague = '';

  // Ortadaki seçenek varsayılan gelir (Tiki Taka Toe'da 3 tur, saatli
  // modlarda 50 saniye); kurucu isterse değiştirir.
  late int _rounds = _mode.roundOptions[1];
  late int _clockSeconds = _mode.clockOptions[1];

  List<GameCategory> _categories = const [];
  String? _selectedCategoryId;
  bool _loadingCategories = false;

  String? _roomCode;
  bool _creating = true;
  bool _applyingSettings = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _reserveRoom();
    if (_mode.needsCategory) _loadCategories();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _reserveRoom() async {
    setState(() {
      _creating = true;
      _error = null;
    });

    try {
      final ticket = await ApiService.createRoom(
        mode: _mode,
        leagueId: _mode.needsLeague ? Session.instance.leagueId : null,
        roundCount: _mode.needsRoundCount ? _rounds : null,
        clockSeconds: _mode.isClockBased ? _clockSeconds : null,
      );
      if (!mounted) return;
      setState(() {
        _roomCode = ticket.code;
        _creating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = 'Sunucuya ulaşılamadı. Bağlantını kontrol et.';
      });
    }
  }

  /// Kurucuya sunulacak kategori seçeneklerini çeker.
  Future<void> _loadCategories() async {
    setState(() => _loadingCategories = true);
    final fetched = await ApiService.categories(count: _categoryChoices);
    if (!mounted) return;
    setState(() {
      _categories = fetched;
      _loadingCategories = false;
      // Listeden düşen bir kategori seçiliyse seçim temizlenir.
      if (!fetched.any((c) => c.id == _selectedCategoryId)) {
        _selectedCategoryId = null;
      }
    });
  }

  void _copyCode() {
    final code = _roomCode;
    if (code == null) return;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Oda kodu kopyalandı: $code'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _mode.colors.last,
        ),
      );
  }

  void _onPlayPressed() {
    if (_roomCode == null) return;

    if (_mode.needsLeague && _selectedLeague.isEmpty) {
      GameDialogs.showWarning(
        context,
        title: 'LİG SEÇ',
        message: 'Oyuna başlamadan önce bir lig seçmelisin.',
      );
      return;
    }

    if (_mode.needsLeague) {
      Session.instance.leagueId = _catalog.leagueId(_selectedLeague);
    }

    _enterWaitingRoom();
  }

  /// Seçimleri sunucudaki odaya işler, sonra bekleme odasına geçer.
  ///
  /// Oda kodu ekran açılırken rezerve edildiği için seçimler sunucuya ayrıca
  /// bildirilmeli; aksi halde oyun varsayılan ayarlarla başlıyordu.
  Future<void> _enterWaitingRoom() async {
    Session.instance
      ..roundCount = _rounds
      ..clockSeconds = _clockSeconds
      ..categoryId = _selectedCategoryId;

    setState(() => _applyingSettings = true);

    try {
      await ApiService.updateRoom(
        code: _roomCode!,
        mode: _mode,
        leagueId: _mode.needsLeague ? Session.instance.leagueId : null,
        roundCount: _mode.needsRoundCount ? _rounds : null,
        clockSeconds: _mode.isClockBased ? _clockSeconds : null,
        categoryId: _mode.needsCategory ? _selectedCategoryId : null,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _applyingSettings = false);
      GameDialogs.showWarning(
        context,
        title: 'BAĞLANTI HATASI',
        message: 'Oda ayarları kaydedilemedi.\nTekrar dene.',
      );
      return;
    }

    if (!mounted) return;
    setState(() => _applyingSettings = false);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WaitingRoomScreen(
          roomCode: _roomCode!,
          mode: _mode,
          isHost: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _roomCode != null && !_applyingSettings;

    return Scaffold(
      body: Stack(
        children: [
          PlainBackground(accent: _mode.colors.first),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      GlassBackButton(
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const Spacer(),
                      Flexible(child: _ModeBadge(mode: _mode)),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                    child: Column(
                      children: [
                        _buildRoomCode(),
                        const SizedBox(height: 26),
                        ..._buildSetupSections(),
                        const SizedBox(height: 8),
                        PrimaryButton(
                          key: const ValueKey('btn_play'),
                          label: 'OYUNU BAŞLAT',
                          icon: Icons.sports_esports_rounded,
                          enabled: ready,
                          colors: _mode.colors,
                          onTap: _onPlayPressed,
                        ),
                        if (_applyingSettings) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Ayarlar kaydediliyor...',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Moda göre değişen ayar bölümleri; her biri numaralandırılır.
  List<Widget> _buildSetupSections() {
    final sections = <Widget>[];
    var step = 1;

    void add(Widget child) {
      sections
        ..add(child)
        ..add(const SizedBox(height: 22));
    }

    if (_mode.needsLeague) {
      add(_SetupSection(
        step: step++,
        title: 'LİG SEÇ',
        hint: 'Tahtadaki kulüpler bu ligden gelir',
        accent: _mode.colors.last,
        child: _buildLeaguePicker(),
      ));
    }

    if (_mode.needsCategory) {
      add(_SetupSection(
        step: step++,
        title: 'KATEGORİ SEÇ',
        hint: 'İkiniz de bu kategoriden futbolcu yazacaksınız',
        accent: _mode.colors.last,
        trailing: IconButton(
          onPressed: _loadingCategories ? null : _loadCategories,
          icon: const Icon(Icons.refresh_rounded,
              color: Colors.white70, size: 20),
          tooltip: 'Yeni seçenekler',
        ),
        child: _buildCategoryPicker(),
      ));
    }

    if (_mode.needsRoundCount) {
      add(_SetupSection(
        step: step++,
        title: _mode == GameMode.tikiTakaToe ? 'SERİ UZUNLUĞU' : 'TUR SAYISI',
        hint: _mode == GameMode.tikiTakaToe
            ? 'Kaç tahta oynanacak?'
            : 'Kaç eşleşme sorulacak?',
        accent: _mode.colors.last,
        child: _buildRoundPicker(),
      ));
    }

    if (_mode.isClockBased) {
      add(_SetupSection(
        step: step++,
        title: 'SÜRE',
        hint: 'Oyuncu başına saat • yanlış cevap 3 saniye götürür',
        accent: _mode.colors.last,
        child: _buildClockPicker(),
      ));
    }

    return sections;
  }

  Widget _buildRoomCode() {
    if (_creating) {
      return Column(
        children: const [
          SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
                color: Colors.cyanAccent, strokeWidth: 3),
          ),
          SizedBox(height: 12),
          Text('ODA HAZIRLANIYOR...',
              style: TextStyle(
                  color: Colors.white70, fontSize: 12, letterSpacing: 2)),
        ],
      );
    }

    if (_error != null) {
      return NeonPanel(
        colors: const [Colors.redAccent, Colors.orangeAccent],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'TEKRAR DENE',
              icon: Icons.refresh_rounded,
              colors: const [Colors.redAccent, Colors.orangeAccent],
              onTap: _reserveRoom,
            ),
          ],
        ),
      );
    }

    final accent = _mode.colors.last;

    return Column(
      children: [
        Text(
          'ODA KODU',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 12),
        // Dar ekranlarda kutular küçülerek sığar, taşma vermez.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            // Ekranda başka tek haneli yazılar da var (adım numaraları, tur
            // kartları); testler kodu bu anahtarın altından okur.
            key: const ValueKey('room_code'),
            mainAxisSize: MainAxisSize.min,
            children: _roomCode!.split('').map((digit) {
              return ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  width: 54,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: accent.withOpacity(0.55), width: 2),
                    boxShadow: [
                      BoxShadow(color: accent.withOpacity(0.3), blurRadius: 12),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      digit,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [Shadow(color: accent, blurRadius: 10)],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _copyCode,
          icon: const Icon(Icons.copy_rounded, size: 15, color: Colors.white54),
          label: const Text(
            'Kodu kopyala',
            style: TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  Widget _buildLeaguePicker() {
    return Column(
      children: _leagueAssets.entries.map((entry) {
        final selected = _selectedLeague == entry.key;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: GestureDetector(
            key: ValueKey('league_${entry.key}'),
            onTap: () => setState(() => _selectedLeague = entry.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withOpacity(0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? _mode.colors.last.withOpacity(0.8)
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Image.asset(entry.value,
                        fit: BoxFit.contain, height: 48),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: selected ? _mode.colors.last : Colors.white24,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCategoryPicker() {
    if (_loadingCategories) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Center(
          child: CircularProgressIndicator(
              color: _mode.colors.last, strokeWidth: 3),
        ),
      );
    }

    if (_categories.isEmpty) {
      return Column(
        children: [
          Text(
            'Kategoriler yüklenemedi.',
            style:
                TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _loadCategories,
            icon: const Icon(Icons.refresh_rounded,
                size: 16, color: Colors.white70),
            label: const Text('Tekrar dene',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        ],
      );
    }

    return Column(
      children: [
        for (var i = 0; i < _categories.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _CategoryTile(
              key: ValueKey('category_${_categories[i].id}'),
              index: i,
              category: _categories[i],
              selected: _selectedCategoryId == _categories[i].id,
              accent: _mode.colors.last,
              onTap: () => setState(
                () => _selectedCategoryId = _categories[i].id,
              ),
            ),
          ),
        const SizedBox(height: 2),
        _SurpriseTile(
          selected: _selectedCategoryId == null,
          accent: _mode.colors.last,
          onTap: () => setState(() => _selectedCategoryId = null),
        ),
      ],
    );
  }

  Widget _buildRoundPicker() {
    final options = _mode.roundOptions;
    return Row(
      children: [
        for (final rounds in options) ...[
          Expanded(
            child: _OptionCard(
              key: ValueKey('rounds_$rounds'),
              value: '$rounds',
              unit: 'TUR',
              label: _roundLabel(rounds, options),
              icon: _roundIcon(rounds, options),
              colors: _optionColors(options.indexOf(rounds)),
              selected: _rounds == rounds,
              onTap: () => setState(() => _rounds = rounds),
            ),
          ),
          if (rounds != options.last) const SizedBox(width: 10),
        ],
      ],
    );
  }

  Widget _buildClockPicker() {
    final options = _mode.clockOptions;
    return Row(
      children: [
        for (final seconds in options) ...[
          Expanded(
            child: _OptionCard(
              key: ValueKey('clock_$seconds'),
              value: '$seconds',
              unit: 'SANİYE',
              label: _clockLabel(seconds, options),
              icon: _roundIcon(seconds, options),
              colors: _optionColors(options.indexOf(seconds)),
              selected: _clockSeconds == seconds,
              onTap: () => setState(() => _clockSeconds = seconds),
            ),
          ),
          if (seconds != options.last) const SizedBox(width: 10),
        ],
      ],
    );
  }

  String _roundLabel(int value, List<int> options) =>
      switch (options.indexOf(value)) {
        0 => 'HIZLI',
        1 => 'KLASİK',
        _ => 'PRO',
      };

  String _clockLabel(int value, List<int> options) =>
      switch (options.indexOf(value)) {
        0 => 'HIZLI',
        1 => 'KLASİK',
        _ => 'MARATON',
      };

  IconData _roundIcon(int value, List<int> options) =>
      switch (options.indexOf(value)) {
        0 => Icons.flash_on_rounded,
        1 => Icons.emoji_events_rounded,
        _ => Icons.local_fire_department_rounded,
      };

  List<Color> _optionColors(int index) => switch (index) {
        0 => const [Color(0xFF00F260), Color(0xFF0575E6)],
        1 => const [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
        _ => const [Color(0xFFFF512F), Color(0xFFDD2476)],
      };
}

/// Numaralı ayar bölümü başlığı + içeriği.
class _SetupSection extends StatelessWidget {
  const _SetupSection({
    required this.step,
    required this.title,
    required this.hint,
    required this.accent,
    required this.child,
    this.trailing,
  });

  final int step;
  final String title;
  final String hint;
  final Color accent;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [accent, accent.withOpacity(0.55)],
                  ),
                ),
                child: Text(
                  '$step',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Tur sayısı / süre seçeneği kartı.
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    super.key,
    required this.value,
    required this.unit,
    required this.label,
    required this.icon,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  final String value;
  final String unit;
  final String label;
  final IconData icon;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: selected
                ? colors
                : [
                    colors.first.withOpacity(0.18),
                    colors.last.withOpacity(0.18)
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Colors.white.withOpacity(0.7) : Colors.white12,
            width: selected ? 2 : 1.2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colors.first.withOpacity(0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: selected ? Colors.white : Colors.white60, size: 20),
            const SizedBox(height: 6),
            // Dar ekranda rakam + birim küçülerek sığar.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                unit,
                style: TextStyle(
                  color: (selected ? Colors.white : Colors.white54)
                      .withOpacity(selected ? 0.85 : 1),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kategori seçeneği satırı.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    super.key,
    required this.index,
    required this.category,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final int index;
  final GameCategory category;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
        decoration: BoxDecoration(
          color: selected
              ? accent.withOpacity(0.22)
              : Colors.black.withOpacity(0.24),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : Colors.white12,
            width: selected ? 1.8 : 1.1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: accent.withOpacity(0.32), blurRadius: 14)]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? accent : Colors.white.withOpacity(0.08),
              ),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 11),
            // Uzun kategori adları sarar; taşma yerine satıra iner.
            Expanded(
              child: Text(
                category.label,
                style: TextStyle(
                  color:
                      selected ? Colors.white : Colors.white.withOpacity(0.82),
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? accent : Colors.white24,
              size: 21,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Sürpriz" seçeneği: kategoriyi sunucu belirler.
class _SurpriseTile extends StatelessWidget {
  const _SurpriseTile({
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('category_surprise'),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? Colors.amberAccent.withOpacity(0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Colors.amberAccent : Colors.white12,
            width: selected ? 1.6 : 1.1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.casino_rounded,
                color: selected ? Colors.amberAccent : Colors.white38,
                size: 21),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                'Sürpriz olsun — kategoriyi oyun başlarken öğrenin',
                style: TextStyle(
                  color:
                      selected ? Colors.white : Colors.white.withOpacity(0.55),
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.mode});

  final GameMode mode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: mode.colors),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: mode.colors.first.withOpacity(0.45), blurRadius: 14),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(mode.icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              mode.title.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
