import 'dart:async';

import 'package:flutter/material.dart';

import 'package:footttball/data/services/api_service.dart';
import 'package:footttball/shared/widgets/player_avatar.dart';

/// Yazdıkça futbolcu öneren cevap alanı.
///
/// Öneriler girişin üstünde açılır (klavye altta kaldığı için) ve seçilen
/// futbolcu doğrudan gönderilir. Süre işlerken yazım/aksan hatasıyla vakit
/// kaybedilmesini önler.
class PlayerSuggestionField extends StatefulWidget {
  const PlayerSuggestionField({
    super.key,
    required this.controller,
    required this.onSubmit,
    required this.accent,
    this.enabled = true,
    this.hint = 'Futbolcu adı yaz...',
    this.autofocus = false,
    this.maxSuggestions = 6,
    this.showSuggestions = true,
    this.showPlayerDetails = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final Color accent;
  final bool enabled;
  final String hint;
  final bool autofocus;
  final int maxSuggestions;

  /// Kapalıysa hiç öneri gösterilmez (Son Harf modunda oyunun özü budur).
  final bool showSuggestions;

  /// Açıksa önerilerde ülke ve kulüp de görünür; kapalıyken yalnızca isim.
  final bool showPlayerDetails;

  @override
  State<PlayerSuggestionField> createState() => _PlayerSuggestionFieldState();
}

class _PlayerSuggestionFieldState extends State<PlayerSuggestionField> {
  Timer? _debounce;
  List<Map<String, dynamic>> _suggestions = const [];
  bool _loading = false;

  /// Yalnızca en son isteğin sonucu gösterilir; geç dönenler yok sayılır.
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();

    if (!widget.showSuggestions) return;

    if (query.trim().length < 2) {
      setState(() {
        _suggestions = const [];
        _loading = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 160), () => _fetch(query));
  }

  Future<void> _fetch(String query) async {
    final requestId = ++_requestId;
    setState(() => _loading = true);

    try {
      final results = await ApiService.searchPlayers(query);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _suggestions = results.take(widget.maxSuggestions).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _suggestions = const [];
        _loading = false;
      });
    }
  }

  void _clearSuggestions() {
    _debounce?.cancel();
    if (_suggestions.isNotEmpty || _loading) {
      setState(() {
        _suggestions = const [];
        _loading = false;
      });
    }
  }

  void _submit(String value) {
    final answer = value.trim();
    if (answer.isEmpty) return;
    _clearSuggestions();
    widget.onSubmit(answer);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showSuggestions &&
            widget.enabled &&
            (_suggestions.isNotEmpty || _loading))
          _buildSuggestions(),
        _buildInput(),
      ],
    );
  }

  Widget _buildSuggestions() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF16132C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: widget.accent.withOpacity(0.4), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _loading && _suggestions.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) =>
                  Divider(color: Colors.white.withOpacity(0.06), height: 1),
              itemBuilder: (context, index) => _tile(_suggestions[index]),
            ),
    );
  }

  Widget _tile(Map<String, dynamic> player) {
    final name = player['name'] as String? ?? '';
    final country = player['country'] as String?;
    final clubs = ((player['clubs'] as List?) ?? const []).cast<String>();
    // Oyun eski takımları da kabul ettiği için kulüp geçmişi gösterilir.
    final clubLine = clubs.isEmpty ? (player['club'] as String? ?? '') : clubs.join(' • ');

    return InkWell(
      onTap: () => _submit(name),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: widget.showPlayerDetails ? 9 : 11,
        ),
        child: Row(
          children: [
            PlayerAvatar(
              name: name,
              imageUrl: player['image_url'] as String?,
              size: widget.showPlayerDetails ? 38 : 32,
              borderColor: widget.accent,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: widget.showPlayerDetails
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (country != null && country.isNotEmpty) ...[
                              CountryFlag(country: country, width: 17),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                clubLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  // Oyunun zorluğunu korumak için yalnızca isim gösterilir.
                  : Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
            Icon(Icons.north_east_rounded,
                color: widget.accent.withOpacity(0.75), size: 17),
          ],
        ),
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              textInputAction: TextInputAction.send,
              onChanged: _onChanged,
              onSubmitted: _submit,
              style: const TextStyle(color: Colors.white, fontSize: 15.5),
              cursorColor: widget.accent,
              decoration: InputDecoration(
                hintText: widget.enabled ? widget.hint : 'Rakibin sırası...',
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
                filled: true,
                fillColor: Colors.white.withOpacity(widget.enabled ? 0.09 : 0.04),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: widget.controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white38, size: 18),
                        onPressed: () {
                          widget.controller.clear();
                          _clearSuggestions();
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: widget.enabled ? () => _submit(widget.controller.text) : null,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: widget.enabled
                      ? [widget.accent, widget.accent.withOpacity(0.7)]
                      : [Colors.white12, Colors.white10],
                ),
                boxShadow: widget.enabled
                    ? [
                        BoxShadow(
                          color: widget.accent.withOpacity(0.45),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                Icons.send_rounded,
                color: widget.enabled ? Colors.white : Colors.white24,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
