import 'package:flutter/material.dart';

import 'package:footttball/core/session.dart';
import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/services/api_service.dart';
import 'package:footttball/shared/widgets/app_background.dart';

/// Genel skor tablosu.
///
/// Üstte kendi kartın (sıra, toplam puan, mod başına dağılım), altında
/// seçilen sekmenin ilk 50'si. Sekmeler: Genel, dört oyun modu, Günün
/// Tahtası. Puanlar sunucuda tutulur; burada yalnız gösterilir.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _Tab {
  const _Tab(this.id, this.label, this.icon, this.colors);
  final String id;
  final String label;
  final IconData icon;
  final List<Color> colors;
}

final List<_Tab> _tabs = [
  const _Tab('all', 'GENEL', Icons.emoji_events_rounded,
      [Color(0xFFFFD200), Color(0xFFF7971E)]),
  for (final m in GameMode.values)
    _Tab(m.id, m.title.toUpperCase(), m.icon, m.colors),
  const _Tab('daily', 'GÜNÜN TAHTASI', Icons.calendar_today_rounded,
      [Color(0xFF11998E), Color(0xFF38EF7D)]),
];

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  String _mode = 'all';
  Leaderboard? _board;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final board = await ApiService.leaderboard(mode: _mode);
      if (!mounted || board.mode != _mode) return;
      setState(() {
        _board = board;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _select(String id) {
    if (id == _mode) return;
    setState(() => _mode = id);
    _load();
  }

  _Tab get _tab => _tabs.firstWhere((t) => t.id == _mode);

  @override
  Widget build(BuildContext context) {
    final me = _board?.me;
    return Scaffold(
      body: Stack(
        children: [
          const PlainBackground(),
          SafeArea(
            child: Column(
              children: [
                _Header(onBack: () => Navigator.of(context).pop()),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _tabs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => _TabChip(
                      tab: _tabs[i],
                      selected: _tabs[i].id == _mode,
                      onTap: () => _select(_tabs[i].id),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (me != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _MeCard(me: me, tab: _tab),
                  ),
                const SizedBox(height: 12),
                Expanded(child: _body()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.cyanAccent),
      );
    }
    if (_failed) {
      return _Empty(
        icon: Icons.wifi_off_rounded,
        text: 'Skor tablosu yüklenemedi',
        action: TextButton(
          onPressed: _load,
          child: const Text('TEKRAR DENE',
              style: TextStyle(color: Colors.cyanAccent)),
        ),
      );
    }
    final entries = _board?.entries ?? const [];
    if (entries.isEmpty) {
      return const _Empty(
        icon: Icons.hourglass_empty_rounded,
        text: 'Henüz puan yok — ilk sen ol!',
      );
    }
    final myId = Session.instance.playerId;
    return RefreshIndicator(
      color: Colors.cyanAccent,
      backgroundColor: const Color(0xFF14142A),
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _Row(
          entry: entries[i],
          tab: _tab,
          isMe: entries[i].playerId == myId,
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white70),
          ),
          const Expanded(
            child: NeonTitle(
              'SKOR TABLOSU',
              fontSize: 24,
              colors: [Colors.white, Color(0xFFFFD200)],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.tab,
    required this.selected,
    required this.onTap,
  });
  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey('lb_tab_${tab.id}'),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: selected
              ? LinearGradient(colors: tab.colors)
              : LinearGradient(colors: [
                  Colors.white.withOpacity(0.08),
                  Colors.white.withOpacity(0.08),
                ]),
          border: Border.all(
            color: selected
                ? Colors.white.withOpacity(0.6)
                : Colors.white.withOpacity(0.15),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tab.icon,
                size: 16, color: selected ? Colors.black87 : Colors.white70),
            const SizedBox(width: 6),
            Text(
              tab.label,
              style: TextStyle(
                color: selected ? Colors.black87 : Colors.white70,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kullanıcının kendi durumu. Genel sekmede mod dağılımı da görünür.
class _MeCard extends StatelessWidget {
  const _MeCard({required this.me, required this.tab});
  final MySummary me;
  final _Tab tab;

  @override
  Widget build(BuildContext context) {
    final points = tab.id == 'all' ? me.total : (me.perMode[tab.id] ?? 0);
    final rankText = me.rank == null ? '—' : '#${me.rank}';
    return NeonPanel(
      colors: tab.colors,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: tab.colors.first.withOpacity(0.25),
                child: Text(
                  Session.instance.displayName.characters.first.toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Session.instance.displayName.toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      tab.id == 'all' ? 'Genel sıra $rankText' : tab.label,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.6), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$points',
                    key: const ValueKey('lb_my_points'),
                    style: TextStyle(
                      color: tab.colors.first,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  Text('PUAN',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 10,
                          letterSpacing: 1.5)),
                ],
              ),
            ],
          ),
          if (tab.id == 'all') ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final t in _tabs.where((t) => t.id != 'all'))
                  _MiniStat(tab: t, value: me.perMode[t.id] ?? 0),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.tab, required this.value});
  final _Tab tab;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tab.icon, size: 13, color: tab.colors.first),
          const SizedBox(width: 5),
          Text('$value',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.tab, required this.isMe});
  final LeaderboardEntry entry;
  final _Tab tab;
  final bool isMe;

  static const _medals = [
    Color(0xFFFFD200),
    Color(0xFFC0C0C0),
    Color(0xFFCD7F32)
  ];

  @override
  Widget build(BuildContext context) {
    final medal = entry.rank <= 3 ? _medals[entry.rank - 1] : null;
    final subtitle = tab.id == 'daily'
        ? 'en iyi gün ${entry.bestDaily}/9'
        : '${entry.wins} galibiyet · ${entry.matches} maç';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isMe
            ? tab.colors.first.withOpacity(0.18)
            : Colors.white.withOpacity(0.05),
        border: Border.all(
          color: isMe
              ? tab.colors.first.withOpacity(0.7)
              : Colors.white.withOpacity(medal != null ? 0.2 : 0.08),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: medal != null
                ? Icon(Icons.emoji_events_rounded, color: medal, size: 24)
                : Text(
                    '${entry.rank}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: isMe ? FontWeight.w900 : FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.5), fontSize: 11.5),
                ),
              ],
            ),
          ),
          Text(
            '${entry.points}',
            style: TextStyle(
              color: medal ?? tab.colors.first,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: Colors.white.withOpacity(0.35)),
          const SizedBox(height: 10),
          Text(text, style: TextStyle(color: Colors.white.withOpacity(0.6))),
          if (action != null) action!,
        ],
      ),
    );
  }
}
