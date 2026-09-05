"""Ülke adı -> ISO kodu çözümlemesi."""

import pycountry

from app.db.reference_data import FLAG_MAPPINGS


def get_iso_code(name: str | None) -> str | None:
    """Ülke adından ISO alpha-2 kodu üretir. Bulunamazsa None döner.

    Eski sürüm `search_fuzzy` sonucunda bazen liste döndürüyordu; burada her
    dalda düz string döndürülmesi garanti altına alındı.
    """
    if not name:
        return None

    if name in FLAG_MAPPINGS:
        return FLAG_MAPPINGS[name]

    if name == "England":
        return "GB"

    try:
        return pycountry.subdivisions.lookup(name).code
    except LookupError:
        pass

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
