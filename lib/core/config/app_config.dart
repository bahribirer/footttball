/// Ortam ayarları.
///
/// Yerel sunucuya bağlanmak için:
///   flutter run --dart-define=API_BASE=http://10.0.2.2:8000 --dart-define=WS_BASE=ws://10.0.2.2:8000
/// (Android emülatöründe 10.0.2.2, iOS simülatöründe 127.0.0.1 ana makineye gider.)
class AppConfig {
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://tikitakatoe.com',
  );

  static const String wsBase = String.fromEnvironment(
    'WS_BASE',
    defaultValue: 'wss://tikitakatoe.com',
  );

  /// Sunucu tarafı yanıt beklenen isteklerde kullanılan zaman aşımı.
  static const Duration requestTimeout = Duration(seconds: 15);

  /// WebSocket canlılık sinyali aralığı (sunucudaki boşta kalma süresinden kısa).
  static const Duration heartbeatInterval = Duration(seconds: 20);
}
