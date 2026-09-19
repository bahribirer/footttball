import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Oyun ses efektleri.
///
/// Kısa efektler (dokunma, doğru, yanlış, tur başı, saat, maç sonu).
/// Sesler `assets/sounds/` altında sentezlenmiş küçük WAV'lar; müzik yok.
/// Kapatma tercihi cihazda saklanır. Ses hatası oyunu asla durdurmaz —
/// her çağrı yutulur.
enum Sfx { tap, correct, wrong, tick, clue, win, lose, start, turn }

class Sound {
  Sound._();
  static final Sound instance = Sound._();

  static const _prefKey = 'sound_enabled';

  bool _enabled = true;
  bool get enabled => _enabled;

  /// Aynı anda çalabilen efekt sayısı; art arda gelen "tick"ler birbirini
  /// kesmesin diye küçük bir havuz.
  final List<AudioPlayer> _pool = [];
  int _next = 0;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefKey) ?? true;
    } catch (_) {
      _enabled = true;
    }
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.game,
            audioFocus: AndroidAudioFocus.none,
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        _pool.add(AudioPlayer()..setReleaseMode(ReleaseMode.stop));
      }
    } catch (_) {
      // Ses motoru kurulamadıysa sessiz devam.
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {}
  }

  void play(Sfx sfx) {
    if (!_enabled || _pool.isEmpty) return;
    final player = _pool[_next % _pool.length];
    _next++;
    // Beklenmez: efekt arayüzü hiçbir zaman geciktirmesin.
    player
        .play(AssetSource('sounds/${sfx.name}.wav'), volume: 0.8)
        .catchError((_) {});
  }
}
