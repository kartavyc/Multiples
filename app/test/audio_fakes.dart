// Shared FAKE audio backend for the R18 audio tests (unit + widget). Records
// every channel call; plays no native audio (headless-safe).

import 'package:multiples_app/audio.dart';

/// One recorded call on a fake channel.
class FakeCall {
  FakeCall(this.op, {this.arg, this.value});
  final String op; // 'play' | 'setVolume' | 'stop' | 'loop' | 'pause' | ...
  final String? arg; // asset path (play) / loop flag
  final double? value; // volume

  @override
  String toString() => 'FakeCall($op, arg=$arg, value=$value)';
}

/// A recording [AudioPlayerHandle].
class FakePlayer implements AudioPlayerHandle {
  final List<FakeCall> calls = [];
  String? lastAsset;
  double volume = 0;
  bool looping = false;
  bool playing = false;

  List<FakeCall> get plays => calls.where((c) => c.op == 'play').toList();

  @override
  Future<void> setVolume(double v) async {
    volume = v;
    calls.add(FakeCall('setVolume', value: v));
  }

  @override
  Future<void> play(String assetPath, {double volume = 1.0}) async {
    lastAsset = assetPath;
    this.volume = volume;
    playing = true;
    calls.add(FakeCall('play', arg: assetPath, value: volume));
  }

  @override
  Future<void> setLoop(bool loop) async {
    looping = loop;
    calls.add(FakeCall('loop', arg: '$loop'));
  }

  @override
  Future<void> stop() async {
    playing = false;
    calls.add(FakeCall('stop'));
  }

  @override
  Future<void> pause() async {
    playing = false;
    calls.add(FakeCall('pause'));
  }

  @override
  Future<void> resume() async {
    playing = true;
    calls.add(FakeCall('resume'));
  }

  @override
  Future<void> dispose() async => calls.add(FakeCall('dispose'));
}

/// A recording [AudioBackend]: the BGM channel is the FIRST player created.
class FakeBackend implements AudioBackend {
  final List<FakePlayer> players = [];

  FakePlayer get bgm => players.first;
  List<FakePlayer> get sfxPool => players.sublist(1);

  /// Every asset name played across the whole SFX pool, in order of channel.
  List<String> get sfxAssetsPlayed => [
        for (final p in sfxPool)
          for (final c in p.plays) c.arg!,
      ];

  /// True iff [asset] was played on any SFX channel.
  bool playedSfx(String asset) => sfxAssetsPlayed.contains(asset);

  @override
  AudioPlayerHandle createPlayer() {
    final p = FakePlayer();
    players.add(p);
    return p;
  }
}
