"""Ülke adı -> ISO kodu çözümlemesi."""

import pycountry

from app.db.reference_data import FLAG_MAPPINGS


# Alt bölge yalnız Britanya ulusları için; genel subdivision araması
# "Georgia" → US-GA, "Luxembourg" → BE-WLX, "Mali" → GN-ML üretiyordu.
_UK_NATIONS = {
    "England": "GB-ENG",
    "Scotland": "GB-SCT",
    "Wales": "GB-WLS",
    "Northern Ireland": "GB-NIR",
}

# Tarihî devletler ve pycountry'nin yanlış/eksik çözdüğü adlar → bugünkü
# bayrak (flagcdn kodu). Efsanelerin uyruğu Wikidata'dan bu adlarla geliyor.
_SPECIAL = {
    "Kosovo": "XK",
    "Curacao": "CW",
    "Curaçao": "CW",
    "Aruba": "AW",
    "Zaire": "CD",
    "Gagauzia": "MD",
    "Tahiti": "PF",
    "Neukaledonien": "NC",
    "Chinese Taipei": "TW",
    "Northern Cyprus": "CY",
    "Republic of Ireland": "IE",
    "Soviet Union": "RU",
    "Russian Empire": "RU",
    "Russian Socialist Federative Soviet Republic": "RU",
    "Chechnya": "RU",
    "Yugoslavia": "RS",
    "Kingdom of Yugoslavia": "RS",
    "Socialist Federal Republic of Yugoslavia": "RS",
    "Federal Republic of Yugoslavia": "RS",
    "Serbia and Montenegro": "RS",
    "Kingdom of Serbs, Croats and Slovenes": "RS",
    "Czechoslovakia": "CZ",
    "Protectorate of Bohemia and Moravia": "CZ",
    "East Germany": "DE",
    "German Democratic Republic": "DE",
    "West Germany": "DE",
    "German Empire": "DE",
    "German Reich": "DE",
    "Weimar Republic": "DE",
    "Nazi Germany": "DE",
    "Kingdom of Bavaria": "DE",
    "Kingdom of Italy": "IT",
    "Republic of Venice": "IT",
    "Free State of Fiume": "HR",
    "Kingdom of Hungary": "HU",
    "Austria–Hungary": "AT",
    "Austria-Hungary": "AT",
    "Cisleithania": "AT",
    "Kingdom of Portugal": "PT",
    "Ottoman Empire": "TR",
    "British Empire": "GB",
    "United Kingdom of Great Britain and Ireland": "GB",
    "British Hong Kong": "HK",
    "Dominion of India": "IN",
    "Empire of Japan": "JP",
    "Pahlavi Iran": "IR",
    "People's Republic of Bulgaria": "BG",
    "Polish People's Republic": "PL",
    "Second Polish Republic": "PL",
    "Republic of Abkhazia": "GE",
    "Georgian SSR": "GE",
    "Ukrainian Soviet Socialist Republic": "UA",
    "Ukrainian People's Republic": "UA",
    "Ukrainian State": "UA",
    "Sahrawi Arab Democratic Republic": "EH",
    "South-West Africa": "NA",
    "Spanish protectorate in Morocco": "MA",
    "French protectorate of Tunisia": "TN",
    "Saint-Martin": "MF",
    "Sint Maarten": "SX",
    "Guadeloupe": "GP",
    "Martinique": "MQ",
    "Reunion": "RE",
    "Macedonia": "MK",
    "Swaziland": "SZ",
    "Burma": "MM",
    "Palestine": "PS",
    "Zimbabwe Rhodesia": "ZW",
    "Rhodesia": "ZW",
}


def get_iso_code(name: str | None) -> str | None:
    """Ülke adından bayrak kodu (ISO alpha-2 ya da GB-ENG gibi) üretir.

    Bulunamazsa None döner. Bulanık arama en son ve yalnız ülkeler
    arasında; alt bölge araması yok.
    """
    if not name:
        return None

    if name in FLAG_MAPPINGS:
        return FLAG_MAPPINGS[name]
    if name in _UK_NATIONS:
        return _UK_NATIONS[name]
    if name in _SPECIAL:
        return _SPECIAL[name]

    lookup_name = "Türkiye" if name == "Turkey" else name
    try:
        return pycountry.countries.lookup(lookup_name).alpha_2
    except LookupError:
        pass

    try:
        matches = pycountry.countries.search_fuzzy(name)
        if matches:
            return matches[0].alpha_2
    except LookupError:
        pass

    return None


def flag_url(country: str | None, width: int = 40) -> str | None:
    code = get_iso_code(country)
    if not code:
        return None
    return f"https://flagcdn.com/w{width}/{code.lower()}.png"
