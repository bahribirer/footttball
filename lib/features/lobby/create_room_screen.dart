import 'package:flutter/material.dart';

import 'package:footttball/core/session.dart';
import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/services/api_service.dart';
import 'package:footttball/data/services/league_catalog.dart';
import 'package:footttball/features/lobby/waiting_room_screen.dart';
import 'package:footttball/shared/widgets/app_background.dart';
import 'package:footttball/shared/widgets/game_dialogs.dart';

/// Oda kurma ekranı. Oda kodunu sunucu üretir; iki kurucunun aynı kodu
/// almasından kaynaklanan çakışma böylece ortadan kalkar.
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

  final _catalog = LeagueCatalog();
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  GameMode get _mode => Session.instance.selectedMode;

  String _selectedLeague = '';
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
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _reserveRoom();
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
        roundCount: Session.instance.roundCount,
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
      _showRoundSelection();
    } else {
      _enterWaitingRoom(_mode == GameMode.playerGuess ? 5 : 1);
    }
  }

  /// Seçimleri sunucudaki odaya işler, sonra bekleme odasına geçer.
  ///
  /// Oda kodu ekran açılırken rezerve edildiği için lig ve tur seçimi
  /// sunucuya ayrıca bildirilmeli; aksi halde oyun varsayılan ayarlarla
  /// (rastgele lig, tek tur) başlıyordu.
  Future<void> _enterWaitingRoom(int rounds) async {
    Session.instance.roundCount = rounds;
    setState(() => _applyingSettings = true);

    try {
      await ApiService.updateRoom(
        code: _roomCode!,
        mode: _mode,
        leagueId: _mode.needsLeague ? Session.instance.leagueId : null,
        roundCount: rounds,
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
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          const BoardBackground(dim: 0.3),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: GlassBackButton(onTap: () => Navigator.of(context).maybePop()),
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(top: size.height * 0.13, bottom: 32),
              child: Column(
                children: [
                  _ModeBadge(mode: _mode),
                  const SizedBox(height: 18),
                  _buildRoomCode(),
                  const SizedBox(height: 20),
                  if (_mode.needsLeague) _buildLeaguePicker(size) else _buildModeInfo(),
                  const SizedBox(height: 24),
                  GestureDetector(
                    key: const ValueKey('btn_play'),
                    onTap: (_roomCode == null || _applyingSettings)
                        ? null
                        : _onPlayPressed,
                    child: Opacity(
                      opacity: (_roomCode == null || _applyingSettings) ? 0.4 : 1,
                      child: Image.asset(
                        'images/play.PNG',
                        width: size.width * 0.46,
                        height: size.height * 0.1,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomCode() {
    if (_creating) {
      return Column(
        children: const [
          SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(color: Colors.cyanAccent, strokeWidth: 3),
          ),
          SizedBox(height: 12),
          Text('ODA HAZIRLANIYOR...',
              style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 2)),
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

    return Column(
      children: [
        Text(
          'ODA KODU',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _roomCode!.split('').map((digit) {
            return ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: 50,
                height: 70,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.3),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    digit,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.cyanAccent, blurRadius: 10)],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildLeaguePicker(Size size) {
    return Column(
      children: _leagueAssets.entries.map((entry) {
        final selected = _selectedLeague == entry.key;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: GestureDetector(
            key: ValueKey('league_${entry.key}'),
            onTap: () => setState(() => _selectedLeague = entry.key),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Image.asset(
                  entry.value,
                  fit: BoxFit.contain,
                  width: size.width * 0.7,
                  height: size.height * 0.07,
                ),
                if (selected)
                  Positioned(
                    right: 12,
                    child: Image.asset('images/ok.PNG', width: 24, height: 24),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildModeInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: NeonPanel(
        colors: _mode.colors,
        child: Column(
          children: [
            Icon(_mode.icon, color: Colors.white, size: 34),
            const SizedBox(height: 12),
            Text(
              _mode.description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 14),
            Text(
              _mode == GameMode.playerGuess
                  ? '5 tur • tur başına 3 deneme hakkı'
                  : 'Oyuncu başına 50 saniye • yanlışta 3 saniye ceza',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.amberAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRoundSelection() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: NeonPanel(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NeonTitle('SERİ UZUNLUĞU'),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [1, 3, 5]
                    .map((rounds) => _RoundOption(
                          rounds: rounds,
                          onTap: () {
                            Navigator.of(dialogContext).pop();
                            _enterWaitingRoom(rounds);
                          },
                        ))
                    .toList(),
              ),
              const SizedBox(height: 18),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text(
                  'VAZGEÇ',
                  style: TextStyle(
                    color: Colors.white54,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          Icon(mode.icon, color: Colors.white, size: 17),
          const SizedBox(width: 8),
          Text(
            mode.title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundOption extends StatelessWidget {
  const _RoundOption({required this.rounds, required this.onTap});

  final int rounds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (colors, icon, label) = switch (rounds) {
      1 => ([const Color(0xFF00F260), const Color(0xFF0575E6)], Icons.flash_on_rounded, 'HIZLI'),
      3 => ([const Color(0xFF8E2DE2), const Color(0xFF4A00E0)], Icons.emoji_events_rounded, 'KLASİK'),
      _ => ([const Color(0xFFFF512F), const Color(0xFFDD2476)], Icons.local_fire_department_rounded, 'PRO'),
    };

    return GestureDetector(
      key: ValueKey('rounds_$rounds'),
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 74,
            height: 84,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: colors.first.withOpacity(0.55),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 24),
                const SizedBox(height: 2),
                Text(
                  '$rounds',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
