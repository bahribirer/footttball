import 'dart:async';

import 'package:flutter/material.dart';

import 'package:footttball/data/services/api_service.dart';
import 'package:footttball/shared/widgets/app_background.dart';

/// Oyuncu arama ve seçme kutusu. Seçilen oyuncunun adını `pop` ile döndürür.
class PlayerSearchDialog extends StatefulWidget {
  const PlayerSearchDialog({
    super.key,
    required this.nationality,
    required this.club,
  });

  final String nationality;
  final String club;

  @override
  State<PlayerSearchDialog> createState() => _PlayerSearchDialogState();
}

class _PlayerSearchDialogState extends State<PlayerSearchDialog> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = const [];
  bool _loading = false;

  /// Yalnızca en son aramanın sonucu gösterilir; geç dönen istekler yok sayılır.
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  Future<void> _search(String query) async {
    final requestId = ++_requestId;
    setState(() => _loading = true);

    try {
      final results = await ApiService.searchPlayers(query);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: NeonPanel(
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.66,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(child: _Chip(text: widget.nationality, color: Colors.cyanAccent)),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text('×',
                              style: TextStyle(color: Colors.white54, fontSize: 18)),
                        ),
                        Flexible(child: _Chip(text: widget.club, color: Colors.purpleAccent)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _controller,
                      onChanged: _onChanged,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      cursorColor: Colors.cyanAccent,
                      decoration: InputDecoration(
                        hintText: 'Futbolcu ara...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(Icons.search, color: Colors.cyanAccent),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.08),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildResults()),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'VAZGEÇ',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.cyanAccent, strokeWidth: 3),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _controller.text.trim().length < 2
                ? 'Aramak için en az 2 harf yaz'
                : 'Sonuç bulunamadı',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      itemCount: _results.length,
      separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.06), height: 1),
      itemBuilder: (context, index) {
        final player = _results[index];
        final name = player['name'] as String? ?? '';

        return ListTile(
          dense: true,
          leading: _Avatar(imageUrl: player['image_url'] as String?, name: name),
          title: Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          subtitle: Row(
            children: [
              if (player['flag_url'] != null) ...[
                Image.network(
                  player['flag_url'] as String,
                  width: 18,
                  height: 12,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  [player['club'], player['position']]
                      .whereType<String>()
                      .where((value) => value.isNotEmpty)
                      .join(' • '),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white30),
          onTap: () => Navigator.of(context).pop(name),
        );
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.imageUrl, required this.name});

  final String? imageUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: 19,
      backgroundColor: Colors.white12,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
      ),
    );

    if (imageUrl == null || imageUrl!.isEmpty) return fallback;

    return ClipOval(
      child: Image.network(
        imageUrl!,
        width: 38,
        height: 38,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
  }
}
