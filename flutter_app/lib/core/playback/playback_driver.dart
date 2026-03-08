import 'dart:async';

import 'package:just_audio/just_audio.dart';

abstract class PlaybackDriver {
  Stream<Duration> get positionStream;

  Future<void> setUrl(String url);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> dispose();
}

class JustAudioPlaybackDriver implements PlaybackDriver {
  JustAudioPlaybackDriver({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Future<void> dispose() => _player.dispose();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setUrl(String url) => _player.setUrl(url);
}
