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

  // Öneri listesi girişin üstünde bir katmanda açılır. Eskiden aynı `Column`
  // içinde giriş alanının kardeşiydi; liste her açılıp kapandığında yerleşim
  // yükseliyor ve ekran zıplıyordu.
  final LayerLink _link = LayerLink();
  OverlayEntry? _overlay;

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PlayerSuggestionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sıra rakibe geçtiğinde açık kalan liste kapatılır.
    if (!widget.enabled || !widget.showSuggestions) _clearSuggestions();
  }

  bool get _hasPanel => _suggestions.isNotEmpty || _loading;

  /// Katmanı içeriğe göre açar, kapatır ya da tazeler.
  void _syncOverlay() {
    final shouldShow = widget.showSuggestions && widget.enabled && _hasPanel;

    if (!shouldShow) {
      _removeOverlay();
      return;
    }

    if (_overlay != null) {
      _overlay!.markNeedsBuild();
      return;
    }

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _overlay = OverlayEntry(
      builder: (context) => Positioned(
        width: MediaQuery.of(context).size.width,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          // Panelin altı, giriş alanının üstüne yapışır.
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          child: Material(
            color: Colors.transparent,
            child: _buildSuggestions(),
          ),
        ),
      ),
    );
    overlay.insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
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
    // Katman, çizim sırasında değiştirilemediği için kare sonuna bırakılır.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncOverlay();
    });

    // Yalnızca giriş alanı yer kaplar; öneri listesi üstte yüzer, böylece
    // liste açılıp kapanırken ekran yerinden oynamaz.
    return CompositedTransformTarget(
      link: _link,
      child: _buildInput(),
    );
  }

  Widget _buildSuggestions() {
    // Klavye açıkken panel ekranın kalanına sığmalı; sabit 260 piksel
    // küçük telefonlarda girişin üstünü aşıyordu.
    final available = MediaQuery.of(context).size.height;
    return Container(
      constraints: BoxConstraints(maxHeight: available * 0.32),
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
    final clubLine =
        clubs.isEmpty ? (player['club'] as String? ?? '') : clubs.join(' • ');

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
                fillColor:
                    Colors.white.withOpacity(widget.enabled ? 0.09 : 0.04),
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
            onTap:
                widget.enabled ? () => _submit(widget.controller.text) : null,
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
