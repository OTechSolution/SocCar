import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AlertSoundService  —  Repeating beep alert for 60 seconds
//
// Uses the bundled  assets/sounds/beep.wav  file.
// Requires in pubspec.yaml:
//   dependencies:
//     audioplayers: ^6.0.0
//
//   flutter:
//     assets:
//       - assets/sounds/beep.wav
// ─────────────────────────────────────────────────────────────────────────────
class AlertSoundService {
  static final AlertSoundService _instance = AlertSoundService._internal();
  factory AlertSoundService() => _instance;
  AlertSoundService._internal();

  // Fresh player per alert session — avoids state bugs from reuse
  AudioPlayer? _player;
  Timer?       _autoStopTimer;
  Timer?       _beepTimer;
  bool         _isPlaying = false;

  static const int    _alertDurationSeconds = 60;
  static const int    _beepIntervalSeconds  = 2;
  // Path is RELATIVE to assets/ — do NOT prefix with 'assets/'
  static const String _beepAsset           = 'sounds/beep.wav';

  /// Start the 60-second repeating beep.
  /// Safe to call multiple times — only one alert runs at a time.
  Future<void> startAlert() async {
    if (_isPlaying) return;
    _isPlaying = true;

    // Create a fresh AudioPlayer for this session
    _player = AudioPlayer();
    await _player!.setVolume(1.0);

    // Play immediately on first call
    await _playBeep();

    // Repeat every 2 seconds
    _beepTimer = Timer.periodic(
      const Duration(seconds: _beepIntervalSeconds),
      (_) => _playBeep(),
    );

    // Auto-stop after exactly 60 seconds
    _autoStopTimer = Timer(
      const Duration(seconds: _alertDurationSeconds),
      stopAlert,
    );
  }

  /// Stop immediately — call when resident taps Approve / Deny / timeout.
  void stopAlert() {
    _beepTimer?.cancel();
    _autoStopTimer?.cancel();
    _player?.stop();
    _player?.dispose();
    _player    = null;
    _isPlaying = false;
  }

  bool get isPlaying => _isPlaying;

  Future<void> _playBeep() async {
    try {
      // AssetSource path is relative to the assets/ folder
      await _player?.play(AssetSource(_beepAsset));
    } catch (e) {
      debugPrint('AlertSoundService: beep error: $e');
    }
  }

  void dispose() {
    stopAlert();
  }
}
