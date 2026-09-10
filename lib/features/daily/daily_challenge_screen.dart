import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:footttball/data/services/api_service.dart';
import 'package:footttball/data/services/country_catalog.dart';
import 'package:footttball/shared/widgets/app_background.dart';
import 'package:footttball/shared/widgets/player_avatar.dart';
import 'package:footttball/shared/widgets/player_suggestion_field.dart';

/// Günlük meydan okuma.
///
/// Rakip gerektirmez: herkese aynı 3x3 tahta gelir, her kutu için tek
/// deneme hakkı vardır ve sonuç paylaşılabilir bir emoji ızgarası olur.
///
/// İlerleme cihazda saklanır — uygulamayı kapatıp açmak tekrar denemeye
/// izin verseydi "tek deneme" kuralının anlamı kalmazdı.
class DailyChallengeScreen extends StatefulWidget {
  const DailyChallengeScreen({super.key});

  @override
  State<DailyChallengeScreen> createState() => _DailyChallengeScreenState();
}

class _DailyChallengeScreenState extends State<DailyChallengeScreen> {
  static const _storageKey = 'daily_progress';

  DailyBoard? _board;
  bool _loading = true;
  String? _error;

  /// Kutu başına sonuç: null = denenmedi, true/false = sonuç.
  final Map<int, bool> _results = {};

  /// Doğru bilinen kutularda gösterilen futbolcu adı.
  final Map<int, String> _answers = {};

  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final board = await ApiService.dailyBoard();
    if (!mounted) return;
    if (board == null) {
      setState(() {
        _loading = false;
        _error = 'Bugünün tahtası alınamadı. Bağlantını kontrol et.';
      });
      return;
    }

    await _restoreProgress(board);
    if (!mounted) return;
    setState(() {
      _board = board;
      _loading = false;
    });
  }

  Future<void> _restoreProgress(DailyBoard board) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return;
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      // Gün değiştiyse eski ilerleme geçersiz.
      if (saved['date'] != board.date) return;
      (saved['results'] as Map<String, dynamic>).forEach((key, value) {
        _results[int.parse(key)] = value as bool;
      });
      (saved['answers'] as Map<String, dynamic>? ?? {}).forEach((key, value) {
        _answers[int.parse(key)] = value as String;
      });
    } catch (_) {
      // Bozuk kayıt oyunu engellemesin; sıfırdan başlanır.
    }
  }

  Future<void> _saveProgress() async {
    final board = _board;
    if (board == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode({
          'date': board.date,
          'results': _results.map((k, v) => MapEntry('$k', v)),
          'answers': _answers.map((k, v) => MapEntry('$k', v)),
        }),
      );
    } catch (_) {
      // Kaydedilemezse oyun yine oynanabilir.
    }
  }

  int get _score => _results.values.where((v) => v).length;
  bool get _finished => _results.length == 9;

  Future<void> _openCell(int index) async {
    final board = _board;
    if (board == null || _results.containsKey(index) || _checking) return;

    final nation = board.nations[index ~/ 3];
    final club = board.clubs[index % 3];

    final guess = await showDialog<String>(
      context: context,
      builder: (_) => _GuessDialog(nation: nation, club: club),
    );
    if (guess == null || guess.trim().isEmpty || !mounted) return;

    setState(() => _checking = true);
    final correct = await ApiService.checkPlayer(
      playerName: guess.trim(),
      nationality: nation,
      club: club,
    );
    if (!mounted) return;

    setState(() {
      _results[index] = correct;
      if (correct) _answers[index] = guess.trim();
      _checking = false;
    });
    await _saveProgress();
  }

  Future<void> _share() async {
    final board = _board;
    if (board == null) return;

    final ordered = List<bool>.generate(9, (i) => _results[i] ?? false);
    final text = await ApiService.dailyShareText(
          number: board.number,
          results: ordered,
        ) ??
        'Tiki Taka Toe #${board.number}  $_score/9';

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sonuç panoya kopyalandı')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const PlainBackground(),
          SafeArea(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.cyanAccent),
      );
    }
    final board = _board;
    if (board == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            _error ?? 'Bir şeyler ters gitti.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Column(
      children: [
        _buildHeader(board),
        Expanded(child: SingleChildScrollView(child: _buildGrid(board))),
        if (_finished) _buildFooter(),
      ],
    );
  }

  Widget _buildHeader(DailyBoard board) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              children: [
                NeonTitle('GÜNÜN TAHTASI #${board.number}', fontSize: 18),
                const SizedBox(height: 2),
                Text(
                  _finished
                      ? 'Bitti — $_score/9'
                      : 'Her kutu için tek hakkın var',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildGrid(DailyBoard board) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          // Kulüp başlıkları
          Row(
            children: [
              const SizedBox(width: 78),
              for (final club in board.clubs)
                Expanded(child: _ClubHeader(club: club)),
            ],
          ),
          const SizedBox(height: 6),
          for (var row = 0; row < 3; row++)
            Row(
              children: [
                SizedBox(
                  width: 78,
                  child: _NationHeader(nation: board.nations[row]),
                ),
                for (var col = 0; col < 3; col++)
                  Expanded(
                    child: _Cell(
                      index: row * 3 + col,
                      result: _results[row * 3 + col],
                      answer: _answers[row * 3 + col],
                      onTap: _openCell,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          Text(
            _score == 9
                ? 'Dokuzda dokuz. Bunu paylaşmalısın.'
                : 'Yarın yeni tahta gelecek.',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'SONUCU PAYLAŞ',
            icon: Icons.share_rounded,
            onTap: _share,
          ),
        ],
      ),
    );
  }
}

class _ClubHeader extends StatelessWidget {
  const _ClubHeader({required this.club});

  final String club;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.network(
            ApiService.logoUrl(club),
            width: 34,
            height: 34,
            fit: BoxFit.contain,
            headers: const {"User-Agent": "TikiTaka/1.0"},
            errorBuilder: (_, __, ___) => const Icon(
              Icons.shield_outlined,
              color: Colors.white38,
              size: 26,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            club,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _NationHeader extends StatelessWidget {
  const _NationHeader({required this.nation});

  final String nation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CountryFlag(country: nation, width: 34),
          const SizedBox(height: 4),
          Text(
            CountryCatalog.turkish(nation),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.index,
    required this.result,
    required this.answer,
    required this.onTap,
  });

  final int index;
  final bool? result;
  final String? answer;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final color = result == null
        ? Colors.white10
        : result!
            ? Colors.greenAccent.withValues(alpha: 0.25)
            : Colors.redAccent.withValues(alpha: 0.2);

    return Padding(
      padding: const EdgeInsets.all(3),
      child: AspectRatio(
        aspectRatio: 1,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: result == null ? () => onTap(index) : null,
            child: Center(
              child: result == null
                  ? const Icon(Icons.add_rounded, color: Colors.white38)
                  : Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        answer ?? '✕',
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuessDialog extends StatefulWidget {
  const _GuessDialog({required this.nation, required this.club});

  final String nation;
  final String club;

  @override
  State<_GuessDialog> createState() => _GuessDialogState();
}

class _GuessDialogState extends State<_GuessDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: NeonPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CountryFlag(country: widget.nation, width: 28),
                const SizedBox(width: 8),
                const Text('×',
                    style: TextStyle(color: Colors.white54, fontSize: 16)),
                const SizedBox(width: 8),
                Image.network(
                  ApiService.logoUrl(widget.club),
                  width: 28,
                  height: 28,
                  fit: BoxFit.contain,
                  headers: const {"User-Agent": "TikiTaka/1.0"},
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.shield_outlined,
                    color: Colors.white38,
                    size: 24,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            NeonTitle(
              '${CountryCatalog.turkish(widget.nation)} × ${widget.club}',
              fontSize: 15,
            ),
            const SizedBox(height: 6),
            const Text(
              'Tek hakkın var.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: PlayerSuggestionField(
                controller: _controller,
                autofocus: true,
                hint: 'Futbolcu adı...',
                accent: Colors.cyanAccent,
                onSubmit: (value) => Navigator.of(context).pop(value),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child:
                  const Text('VAZGEÇ', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      ),
    );
  }
}
