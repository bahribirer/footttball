/// Ülke adlarının Türkçe karşılıkları ve bayrak adresleri.
///
/// Veritabanı ülke adlarını İngilizce tutar; doğrulama da bu adlarla yapılır.
/// Arayüzde ise Türkçe ad ve bayrak gösterilir.
class CountryCatalog {
  const CountryCatalog._();

  static const Map<String, String> _turkish = {
    'Albania': 'Arnavutluk', 'Algeria': 'Cezayir', 'Angola': 'Angola',
    'Argentina': 'Arjantin', 'Armenia': 'Ermenistan', 'Australia': 'Avustralya',
    'Austria': 'Avusturya', 'Azerbaijan': 'Azerbaycan', 'Belarus': 'Belarus',
    'Belgium': 'Belçika', 'Benin': 'Benin', 'Bolivia': 'Bolivya',
    'Bosnia-Herzegovina': 'Bosna Hersek', 'Brazil': 'Brezilya',
    'Bulgaria': 'Bulgaristan', 'Burkina Faso': 'Burkina Faso',
    'Cameroon': 'Kamerun', 'Canada': 'Kanada', 'Cape Verde': 'Cabo Verde',
    'Chile': 'Şili', 'China': 'Çin', 'Colombia': 'Kolombiya',
    'Congo': 'Kongo', 'Costa Rica': 'Kosta Rika', "Cote d'Ivoire": 'Fildişi Sahili',
    'Ivory Coast': 'Fildişi Sahili', 'Croatia': 'Hırvatistan', 'Cuba': 'Küba',
    'Curacao': 'Curaçao', 'Cyprus': 'Kıbrıs', 'Czech Republic': 'Çekya',
    'DR Congo': 'Demokratik Kongo', 'Denmark': 'Danimarka',
    'Dominican Republic': 'Dominik Cumhuriyeti', 'Ecuador': 'Ekvador',
    'Egypt': 'Mısır', 'El Salvador': 'El Salvador', 'England': 'İngiltere',
    'Equatorial Guinea': 'Ekvator Ginesi', 'Estonia': 'Estonya',
    'Ethiopia': 'Etiyopya', 'Faroe Islands': 'Faroe Adaları',
    'Finland': 'Finlandiya', 'France': 'Fransa', 'Gabon': 'Gabon',
    'Georgia': 'Gürcistan', 'Germany': 'Almanya', 'Ghana': 'Gana',
    'Greece': 'Yunanistan', 'Guinea': 'Gine', 'Guinea-Bissau': 'Gine-Bissau',
    'Haiti': 'Haiti', 'Honduras': 'Honduras', 'Hungary': 'Macaristan',
    'Iceland': 'İzlanda', 'India': 'Hindistan', 'Indonesia': 'Endonezya',
    'Iran': 'İran', 'Iraq': 'Irak', 'Ireland': 'İrlanda', 'Israel': 'İsrail',
    'Italy': 'İtalya', 'Jamaica': 'Jamaika', 'Japan': 'Japonya',
    'Jordan': 'Ürdün', 'Kazakhstan': 'Kazakistan', 'Kenya': 'Kenya',
    'Korea, North': 'Kuzey Kore', 'Korea, South': 'Güney Kore',
    'South Korea': 'Güney Kore', 'Kosovo': 'Kosova', 'Latvia': 'Letonya',
    'Lebanon': 'Lübnan', 'Liberia': 'Liberya', 'Libya': 'Libya',
    'Lithuania': 'Litvanya', 'Luxembourg': 'Lüksemburg',
    'Madagascar': 'Madagaskar', 'Malaysia': 'Malezya', 'Mali': 'Mali',
    'Malta': 'Malta', 'Mauritania': 'Moritanya', 'Mexico': 'Meksika',
    'Moldova': 'Moldova', 'Montenegro': 'Karadağ', 'Morocco': 'Fas',
    'Mozambique': 'Mozambik', 'Netherlands': 'Hollanda',
    'New Zealand': 'Yeni Zelanda', 'Nigeria': 'Nijerya',
    'North Macedonia': 'Kuzey Makedonya', 'Northern Ireland': 'Kuzey İrlanda',
    'Norway': 'Norveç', 'Panama': 'Panama', 'Paraguay': 'Paraguay',
    'Peru': 'Peru', 'Philippines': 'Filipinler', 'Poland': 'Polonya',
    'Portugal': 'Portekiz', 'Qatar': 'Katar', 'Romania': 'Romanya',
    'Russia': 'Rusya', 'Saudi Arabia': 'Suudi Arabistan',
    'Scotland': 'İskoçya', 'Senegal': 'Senegal', 'Serbia': 'Sırbistan',
    'Sierra Leone': 'Sierra Leone', 'Slovakia': 'Slovakya',
    'Slovenia': 'Slovenya', 'South Africa': 'Güney Afrika', 'Spain': 'İspanya',
    'Suriname': 'Surinam', 'Sweden': 'İsveç', 'Switzerland': 'İsviçre',
    'Syria': 'Suriye', 'Tanzania': 'Tanzanya', 'Thailand': 'Tayland',
    'The Gambia': 'Gambiya', 'Togo': 'Togo',
    'Trinidad and Tobago': 'Trinidad ve Tobago', 'Tunisia': 'Tunus',
    'Turkey': 'Türkiye', 'Türkiye': 'Türkiye', 'Uganda': 'Uganda',
    'Ukraine': 'Ukrayna', 'United Arab Emirates': 'Birleşik Arap Emirlikleri',
    'United States': 'ABD', 'Uruguay': 'Uruguay', 'Uzbekistan': 'Özbekistan',
    'Venezuela': 'Venezuela', 'Vietnam': 'Vietnam', 'Wales': 'Galler',
    'Zambia': 'Zambiya', 'Zimbabwe': 'Zimbabve',
  };

  /// Bayrak dosyası olmayan bölgeler için özel adresler.
  static const Map<String, String> _customFlags = {
    'England': 'https://flagcdn.com/w80/gb-eng.png',
    'Scotland': 'https://flagcdn.com/w80/gb-sct.png',
    'Wales': 'https://flagcdn.com/w80/gb-wls.png',
    'Northern Ireland': 'https://flagcdn.com/w80/gb-nir.png',
    'Kosovo': 'https://flagcdn.com/w80/xk.png',
  };

  static const Map<String, String> _isoOverrides = {
    'Bosnia-Herzegovina': 'ba', 'Cape Verde': 'cv', 'Korea, South': 'kr',
    'South Korea': 'kr', 'Korea, North': 'kp', 'DR Congo': 'cd',
    'Congo': 'cg', "Cote d'Ivoire": 'ci', 'Ivory Coast': 'ci',
    'Turkey': 'tr', 'Türkiye': 'tr', 'Czech Republic': 'cz',
    'The Gambia': 'gm', 'United States': 'us', 'Curacao': 'cw',
    'North Macedonia': 'mk', 'United Arab Emirates': 'ae',
    'Trinidad and Tobago': 'tt', 'Faroe Islands': 'fo',
    'Equatorial Guinea': 'gq', 'Guinea-Bissau': 'gw', 'New Zealand': 'nz',
    'South Africa': 'za', 'Saudi Arabia': 'sa', 'Dominican Republic': 'do',
    'Costa Rica': 'cr', 'El Salvador': 'sv', 'Burkina Faso': 'bf',
    'Sierra Leone': 'sl', 'Cyprus': 'cy',
  };

  /// Ülkenin Türkçe adı; karşılığı yoksa gelen ad olduğu gibi döner.
  static String turkish(String? english) {
    if (english == null || english.isEmpty) return '';
    return _turkish[english] ?? english;
  }

  /// Bayrak görselinin adresi; bilinmeyen ülkelerde null.
  static String? flagUrl(String? english, {int width = 80}) {
    if (english == null || english.isEmpty) return null;

    final custom = _customFlags[english];
    if (custom != null) return custom;

    final iso = _isoOverrides[english] ?? _isoFromName(english);
    if (iso == null) return null;
    return 'https://flagcdn.com/w$width/$iso.png';
  }

  static const Map<String, String> _isoByName = {
    'Albania': 'al', 'Algeria': 'dz', 'Angola': 'ao', 'Argentina': 'ar',
    'Armenia': 'am', 'Australia': 'au', 'Austria': 'at', 'Azerbaijan': 'az',
    'Belarus': 'by', 'Belgium': 'be', 'Benin': 'bj', 'Bolivia': 'bo',
    'Brazil': 'br', 'Bulgaria': 'bg', 'Cameroon': 'cm', 'Canada': 'ca',
    'Chile': 'cl', 'China': 'cn', 'Colombia': 'co', 'Croatia': 'hr',
    'Cuba': 'cu', 'Denmark': 'dk', 'Ecuador': 'ec', 'Egypt': 'eg',
    'Estonia': 'ee', 'Ethiopia': 'et', 'Finland': 'fi', 'France': 'fr',
    'Gabon': 'ga', 'Georgia': 'ge', 'Germany': 'de', 'Ghana': 'gh',
    'Greece': 'gr', 'Guinea': 'gn', 'Haiti': 'ht', 'Honduras': 'hn',
    'Hungary': 'hu', 'Iceland': 'is', 'India': 'in', 'Indonesia': 'id',
    'Iran': 'ir', 'Iraq': 'iq', 'Ireland': 'ie', 'Israel': 'il',
    'Italy': 'it', 'Jamaica': 'jm', 'Japan': 'jp', 'Jordan': 'jo',
    'Kazakhstan': 'kz', 'Kenya': 'ke', 'Latvia': 'lv', 'Lebanon': 'lb',
    'Liberia': 'lr', 'Libya': 'ly', 'Lithuania': 'lt', 'Luxembourg': 'lu',
    'Madagascar': 'mg', 'Malaysia': 'my', 'Mali': 'ml', 'Malta': 'mt',
    'Mauritania': 'mr', 'Mexico': 'mx', 'Moldova': 'md', 'Montenegro': 'me',
    'Morocco': 'ma', 'Mozambique': 'mz', 'Netherlands': 'nl', 'Nigeria': 'ng',
    'Norway': 'no', 'Panama': 'pa', 'Paraguay': 'py', 'Peru': 'pe',
    'Philippines': 'ph', 'Poland': 'pl', 'Portugal': 'pt', 'Qatar': 'qa',
    'Romania': 'ro', 'Russia': 'ru', 'Senegal': 'sn', 'Serbia': 'rs',
    'Slovakia': 'sk', 'Slovenia': 'si', 'Spain': 'es', 'Suriname': 'sr',
    'Sweden': 'se', 'Switzerland': 'ch', 'Syria': 'sy', 'Tanzania': 'tz',
    'Thailand': 'th', 'Togo': 'tg', 'Tunisia': 'tn', 'Uganda': 'ug',
    'Ukraine': 'ua', 'Uruguay': 'uy', 'Uzbekistan': 'uz', 'Venezuela': 've',
    'Vietnam': 'vn', 'Zambia': 'zm', 'Zimbabwe': 'zw',
  };

  static String? _isoFromName(String name) => _isoByName[name];
}
