import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../database/account_store.dart';
import 'local_audio.dart';
import 'playback_ticket.dart';

enum PlaybackPhase {
  idle,
  loading,
  playing,
  paused,
  completed,
  unavailable,
  failed,
}

final class PlayerEvent {
  const PlayerEvent(this.token, this.phase, this.position, this.duration);
  final int token, position, duration;
  final PlaybackPhase phase;
}

abstract interface class AudioPlayerPort {
  Stream<PlayerEvent> get events;
  Future<int> load(Map<String, Object> source);
  Future<void> play(int token);
  Future<void> pause(int token);
  Future<void> seek(int token, int milliseconds);
  Future<void> stop();
}

final class AndroidAudioPlayer implements AudioPlayerPort {
  static const commands = MethodChannel('song_record/playback');
  static const updates = EventChannel('song_record/playback_events');
  @override
  Stream<PlayerEvent> get events =>
      updates.receiveBroadcastStream().map((value) {
        final event = Map<Object?, Object?>.from(value as Map);
        return PlayerEvent(
          event['token'] as int,
          PlaybackPhase.values.byName(event['phase'] as String),
          event['position'] as int,
          event['duration'] as int,
        );
      });
  @override
  Future<int> load(Map<String, Object> source) async =>
      (await commands.invokeMethod<int>('load', source))!;
  @override
  Future<void> play(int token) =>
      commands.invokeMethod<void>('play', {'token': token});
  @override
  Future<void> pause(int token) =>
      commands.invokeMethod<void>('pause', {'token': token});
  @override
  Future<void> seek(int token, int milliseconds) => commands.invokeMethod<void>(
    'seek',
    {'token': token, 'position': milliseconds},
  );
  @override
  Future<void> stop() => commands.invokeMethod<void>('stop');
}

/// No file/metadata mutation. Generation guards reject late account/source callbacks.
final class AudioPlayback extends ChangeNotifier {
  AudioPlayback(
    this.store,
    this.urls,
    this.player, {
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now {
    subscription = player.events.listen(
      _event,
      onError: (_) {
        unawaited(_stop());
        _fail();
      },
    );
  }
  final AccountStore store;
  final PlaybackUrlProvider urls;
  final AudioPlayerPort player;
  final DateTime Function() clock;
  late final StreamSubscription<PlayerEvent> subscription;
  PlaybackPhase phase = PlaybackPhase.idle;
  int position = 0, duration = 0, _token = 0;
  String? _recording;
  PlaybackTicket? _remote;
  bool _renewing = false, _closed = false;
  Future<void> _guard(int token) async {
    store.requireActive();
    if (_closed || token != _token) throw StateError('Playback superseded');
  }

  void _set(PlaybackPhase next) {
    if (_closed) return;
    phase = next;
    notifyListeners();
  }

  void _fail() {
    _set(PlaybackPhase.failed);
  }

  Future<void> start(String recording) async {
    final token = ++_token;
    _recording = recording;
    _remote = null;
    _renewing = false;
    position = 0;
    duration = 0;
    _set(PlaybackPhase.loading);
    try {
      await player.stop();
      await _guard(token);
      final local = await LocalAudioLookup(store).find(recording);
      await _guard(token);
      final source = <String, Object>{
        'token': token,
        'userId': store.userId,
        'environment': store.environment.name,
        'recordingId': recording,
      };
      if (local != null) {
        source.addAll({
          'kind': 'local',
          'path': local.path,
          'size': local.size,
          'sha256': local.checksum,
        });
      } else {
        final ticket = await urls.issue(recording, () => _guard(token));
        await _guard(token);
        _validate(ticket, recording);
        _remote = ticket;
        source.addAll({
          'kind': 'remote',
          'url': ticket.url.toString(),
          'allowLocalHttp': ticket.allowLocalHttp,
        });
      }
      final loaded = await player.load(source);
      await _guard(token);
      duration = loaded;
      if (duration < 1) throw StateError('No playable audio');
      await player.play(token);
      await _guard(token);
      _set(PlaybackPhase.playing);
    } catch (_) {
      if (token == _token && !_closed) {
        if (_remote != null && !_remote!.expiresAt.isAfter(clock().toUtc())) {
          if (!_renewing) {
            _renewing = true;
            await _renew(token);
          }
        } else if (!_renewing) {
          await _stop();
          _fail();
        }
      }
    }
  }

  Future<void> _stop() async {
    try {
      await player.stop();
    } catch (_) {}
  }

  void _validate(PlaybackTicket ticket, String recording) {
    if (ticket.owner != store.userId ||
        ticket.recording != recording ||
        !ticket.expiresAt.isAfter(clock().toUtc()) ||
        ticket.expiresAt.difference(clock().toUtc()) >
            const Duration(minutes: 5, seconds: 15)) {
      throw StateError('Playback ticket identity or expiry mismatch');
    }
  }

  Future<void> pause() async {
    if (phase != PlaybackPhase.playing) return;
    final token = _token;
    try {
      await _guard(token);
      await player.pause(token);
      await _guard(token);
      _set(PlaybackPhase.paused);
    } catch (_) {
      if (token == _token && !_closed) {
        await _stop();
        _fail();
      }
    }
  }

  Future<void> resume() async {
    if (phase != PlaybackPhase.paused) return;
    final token = _token;
    try {
      await _guard(token);
      if (_remote != null && !_remote!.expiresAt.isAfter(clock().toUtc())) {
        if (!_renewing) {
          _renewing = true;
          await _renew(token);
        } else {
          await _stop();
          _fail();
        }
        return;
      }
      await player.play(token);
      await _guard(token);
      _set(PlaybackPhase.playing);
    } catch (_) {
      if (token == _token && !_closed) {
        await _stop();
        _fail();
      }
    }
  }

  Future<void> seek(int milliseconds) async {
    if (!{
      PlaybackPhase.playing,
      PlaybackPhase.paused,
      PlaybackPhase.completed,
    }.contains(phase)) {
      return;
    }
    final token = _token;
    try {
      await _guard(token);
      await player.seek(token, milliseconds.clamp(0, duration));
      await _guard(token);
    } catch (_) {
      if (token == _token && !_closed) {
        await _stop();
        _fail();
      }
    }
  }

  void _event(PlayerEvent event) {
    if (_closed || event.token != _token) return;
    try {
      store.requireActive();
    } catch (_) {
      unawaited(_stop());
      _fail();
      return;
    }
    position = event.position;
    duration = event.duration;
    if (event.phase == PlaybackPhase.failed &&
        _remote != null &&
        !_renewing &&
        !_remote!.expiresAt.isAfter(clock().toUtc())) {
      _renewing = true;
      unawaited(_renew(_token));
      return;
    }
    _set(event.phase);
  }

  Future<void> _renew(int token) async {
    final at = position;
    _set(PlaybackPhase.loading);
    try {
      final ticket = await urls.issue(_recording!, () => _guard(token));
      await _guard(token);
      _validate(ticket, _recording!);
      _remote = ticket;
      final loaded = await player.load({
        'token': token,
        'userId': store.userId,
        'environment': store.environment.name,
        'recordingId': _recording!,
        'kind': 'remote',
        'url': ticket.url.toString(),
        'allowLocalHttp': ticket.allowLocalHttp,
      });
      await _guard(token);
      duration = loaded;
      if (duration < 1) throw StateError('No playable audio');
      await player.seek(token, at.clamp(0, duration));
      await player.play(token);
      await _guard(token);
      _set(PlaybackPhase.playing);
    } catch (_) {
      if (token == _token && !_closed) {
        await _stop();
        _fail();
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    _token++;
    unawaited(subscription.cancel());
    unawaited(_stop());
    super.dispose();
  }
}
