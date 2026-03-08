import 'dart:async';

import 'package:just_audio/just_audio.dart';

abstract class PlaybackDriver {
  Stream<Duration> get positionStream;
  Stream<bool> get playingStream;

  Future<void> setUrls(List<String> urls);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> dispose();
}

class JustAudioPlaybackDriver implements PlaybackDriver {
  JustAudioPlaybackDriver({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Future<void> dispose() => _player.dispose();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setUrls(List<String> urls) async {
    await _player.setAudioSources([
      for (final url in urls) AudioSource.uri(Uri.parse(url)),
    ]);
  }
}
