import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

class AlarmAudioService {
  static final AlarmAudioService _instance = AlarmAudioService._internal();
  factory AlarmAudioService() => _instance;
  AlarmAudioService._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  final ValueNotifier<bool> isRingingNotifier = ValueNotifier<bool>(false);
  String? currentRingingReminderId;

  Future<void> init() async {
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.alarm,
            audioFocus: AndroidAudioFocus.gainTransientExclusive,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.duckOthers,
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('[AlarmAudioService] init error: $e');
    }
  }

  Future<void> startAlarm({
    String sound = 'digital',
    String? customPath,
    String? reminderId,
  }) async {
    try {
      await stopAlarm();
      currentRingingReminderId = reminderId;
      await _player.setReleaseMode(ReleaseMode.loop);

      Source source;
      if (sound == 'custom' && customPath != null && customPath.isNotEmpty && File(customPath).existsSync()) {
        source = DeviceFileSource(customPath);
      } else {
        String assetName = 'alarm_digital.wav';
        if (sound == 'siren') {
          assetName = 'alarm_siren.wav';
        } else if (sound == 'chime') {
          assetName = 'alarm_chime.wav';
        }
        source = AssetSource('sounds/$assetName');
      }

      await _player.play(source);
      _isPlaying = true;
      isRingingNotifier.value = true;
      debugPrint('[AlarmAudioService] Alarm ringing started: $sound');
    } catch (e) {
      debugPrint('[AlarmAudioService] startAlarm error: $e');
    }
  }

  Future<void> previewSound({
    required String sound,
    String? customPath,
  }) async {
    try {
      await stopAlarm();
      await _player.setReleaseMode(ReleaseMode.release);

      Source source;
      if (sound == 'custom' && customPath != null && customPath.isNotEmpty && File(customPath).existsSync()) {
        source = DeviceFileSource(customPath);
      } else {
        String assetName = 'alarm_digital.wav';
        if (sound == 'siren') {
          assetName = 'alarm_siren.wav';
        } else if (sound == 'chime') {
          assetName = 'alarm_chime.wav';
        }
        source = AssetSource('sounds/$assetName');
      }

      await _player.play(source);
      _isPlaying = true;
      isRingingNotifier.value = true;

      // Automatically reset isPlaying when preview finishes
      _player.onPlayerComplete.first.then((_) {
        _isPlaying = false;
        isRingingNotifier.value = false;
      });
    } catch (e) {
      debugPrint('[AlarmAudioService] previewSound error: $e');
    }
  }

  Future<void> stopAlarm() async {
    try {
      await _player.stop();
      _isPlaying = false;
      isRingingNotifier.value = false;
      currentRingingReminderId = null;
      debugPrint('[AlarmAudioService] Alarm stopped');
    } catch (e) {
      debugPrint('[AlarmAudioService] stopAlarm error: $e');
    }
  }

  void dispose() {
    _player.dispose();
  }
}
