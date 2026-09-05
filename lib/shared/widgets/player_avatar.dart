import 'package:flutter/material.dart';

import 'package:footttball/data/services/country_catalog.dart';

/// Oyuncu fotoğrafı. Görsel yoksa ya da yüklenemezse baş harfe düşer.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 40,
    this.borderColor,
  });

  final String name;
  final String? imageUrl;
  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final accent = borderColor ?? Colors.white24;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withOpacity(0.45),
        border: Border.all(color: accent.withOpacity(0.75), width: 1.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: (imageUrl == null || imageUrl!.isEmpty)
          ? _initials(accent)
          : Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _initials(accent),
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : _initials(accent),
            ),
    );
  }

  Widget _initials(Color accent) => Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: accent,
            fontSize: size * 0.42,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
}

/// Ülke bayrağı. Türkçe ad [label] ile birlikte kullanılır.
class CountryFlag extends StatelessWidget {
  const CountryFlag({
    super.key,
    required this.country,
    this.width = 34,
    this.radius = 5,
  });

  /// Veritabanındaki İngilizce ülke adı.
  final String country;
  final double width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = CountryCatalog.flagUrl(country);
    final height = width * 0.68;

    final fallback = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: const Icon(Icons.flag_rounded, color: Colors.white38, size: 16),
    );

    if (url == null) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

/// Bayrak + Türkçe ülke adı.
class CountryLabel extends StatelessWidget {
  const CountryLabel({
    super.key,
    required this.country,
    this.flagWidth = 30,
    this.fontSize = 14,
    this.color = Colors.white,
    this.axis = Axis.horizontal,
  });

  final String country;
  final double flagWidth;
  final double fontSize;
  final Color color;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final flag = CountryFlag(country: country, width: flagWidth);
    final text = Text(
      CountryCatalog.turkish(country),
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
      ),
    );

    if (axis == Axis.vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [flag, const SizedBox(height: 6), text],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [flag, const SizedBox(width: 10), Flexible(child: text)],
    );
  }
}
