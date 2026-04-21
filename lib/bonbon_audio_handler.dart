import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:audio_service/audio_service.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

const String kNowPlayingUrl =
    'https://c34.radioboss.fm/api/info/1015?key=QG5S5BO9HSKG';

const String kCoverBaseUrl =
    'https://bonbonradio.net/wp-content/uploads/radio-covers/';

const String kDefaultCoverUrl = '${kCoverBaseUrl}default.jpeg';

class BonbonAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  Timer? _metadataTimer;

  String? _preparedUrl;
  String? _requestedUrl;
  bool _isStarting = false;

  String _lastTitle = '';
  String _lastArtist = '';
  String _lastAlbum = '';
  String _lastCover = '';

  BonbonAudioHandler() {
    final initialItem = _buildMediaItem(
      album: 'Bonbon Radio',
      title: 'Live Stream',
      artist: 'Bonbon Radio',
      cover: kDefaultCoverUrl,
    );

    mediaItem.add(initialItem);
    queue.add([initialItem]);

    _player.playerStateStream.listen(
      (_) => _broadcastState(),
      onError: (Object error, StackTrace stackTrace) {
        developer.log(
          'playerStateStream error',
          name: 'BonbonAudioHandler',
          error: error,
          stackTrace: stackTrace,
        );

        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            playing: false,
          ),
        );
      },
    );

    _player.playbackEventStream.listen(
      (_) => _broadcastState(),
      onError: (Object error, StackTrace stackTrace) {
        developer.log(
          'playbackEventStream error',
          name: 'BonbonAudioHandler',
          error: error,
          stackTrace: stackTrace,
        );

        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            playing: false,
          ),
        );
      },
    );

    _broadcastState();
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  void _broadcastState() {
    final bool isPlaying = _player.playing;

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.play,
          MediaAction.pause,
          MediaAction.stop,
        },
        androidCompactActionIndices: const [0],
        processingState: _mapProcessingState(_player.processingState),
        playing: isPlaying,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ),
    );
  }

  String _normalizeCoverKey(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9\-]'), '');
  }

  bool _isJingleMetadata(String? artist, String? title, String? album) {
    final combined =
        '${artist ?? ''} ${title ?? ''} ${album ?? ''}'.toLowerCase();
    return combined.contains('jingle');
  }

  Map<String, dynamic> _extractTrackAttributes(Map<String, dynamic> json) {
    final currentTrackInfo = json['currenttrack_info'];

    if (currentTrackInfo is Map<String, dynamic>) {
      final attributes = currentTrackInfo['@attributes'];
      if (attributes is Map<String, dynamic>) {
        return attributes;
      }
    }

    return <String, dynamic>{};
  }

  String _resolveAlbum(Map<String, dynamic> json) {
    final attributes = _extractTrackAttributes(json);
    return (attributes['ALBUM'] ?? '').toString().trim();
  }

  String _resolveArtistFromJson(Map<String, dynamic> json) {
    final attributes = _extractTrackAttributes(json);
    return (attributes['ARTIST'] ?? '').toString().trim();
  }

  String _resolveTitleFromJson(Map<String, dynamic> json) {
    final attributes = _extractTrackAttributes(json);
    return (attributes['TITLE'] ?? '').toString().trim();
  }

  String _buildCoverUrlFromKey(String key) {
    final normalized = _normalizeCoverKey(key);
    if (normalized.isEmpty) return kDefaultCoverUrl;
    return '$kCoverBaseUrl$normalized.jpeg';
  }

  String _resolveCover({
    required String album,
    required String artist,
    required String title,
  }) {
    if (_isJingleMetadata(artist, title, album)) {
      return kDefaultCoverUrl;
    }

    if (album.trim().isNotEmpty) {
      return _buildCoverUrlFromKey(album);
    }

    if (artist.trim().isNotEmpty) {
      return _buildCoverUrlFromKey(artist);
    }

    return kDefaultCoverUrl;
  }

  Uri _safeArtUri(String cover) {
    final value = cover.trim();
    if (value.isEmpty) return Uri.parse(kDefaultCoverUrl);

    final parsed = Uri.tryParse(value);
    if (parsed == null || !parsed.hasScheme) {
      return Uri.parse(kDefaultCoverUrl);
    }

    return parsed;
  }

  MediaItem _buildMediaItem({
    required String album,
    required String title,
    required String artist,
    required String cover,
  }) {
    final normalizedTitle = title.trim().isEmpty ? 'Live Stream' : title.trim();
    final normalizedArtist =
        artist.trim().isEmpty ? 'Bonbon Radio' : artist.trim();

    return MediaItem(
      id: 'bonbonradio-live',
      album: '',
      title: normalizedTitle,
      artist: normalizedArtist,
      artUri: _safeArtUri(cover),
      playable: true,
      displayTitle: normalizedTitle,
      displaySubtitle: normalizedArtist,
      displayDescription: '',
      extras: {
        'cover_slug': album,
      },
    );
  }

  void _publishMediaItem(MediaItem item) {
    mediaItem.add(item);
    queue.add([item]);
  }

  Future<void> _prepareIfNeeded(String url) async {
    if (_preparedUrl == url && _player.processingState != ProcessingState.idle) {
      return;
    }

    await _player.setUrl(url);
    _preparedUrl = url;
  }

  Future<void> playStream(
    String url, {
    required String fallbackTitle,
    required String fallbackArtist,
    required String fallbackCover,
  }) async {
    _requestedUrl = url;
    await _startPlayback(url);
  }

  Future<void> _startPlayback(String url) async {
    if (_isStarting) return;
    _isStarting = true;

    try {
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.loading,
          playing: false,
        ),
      );

      await refreshMetadata(force: true);
      await _prepareIfNeeded(url);
      await _player.play();

      _broadcastState();
      _startMetadataTimer();

      Future<void>.delayed(const Duration(seconds: 1), () async {
        if (_player.playing) {
          await refreshMetadata(force: true);
        }
      });
    } catch (e, st) {
      developer.log(
        '_startPlayback failed',
        name: 'BonbonAudioHandler',
        error: e,
        stackTrace: st,
      );

      _preparedUrl = null;

      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          playing: false,
        ),
      );

      rethrow;
    } finally {
      _isStarting = false;
    }
  }

  Future<void> refreshMetadata({bool force = false}) async {
    try {
      final res = await http.get(
        Uri.parse(kNowPlayingUrl),
        headers: const {
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode != 200) return;

      final json = jsonDecode(res.body) as Map<String, dynamic>;

      String artist = _resolveArtistFromJson(json);
      String title = _resolveTitleFromJson(json);
      final String album = _resolveAlbum(json);

      final rawNowPlaying = (json['nowplaying'] ?? '').toString().trim();

      if ((artist.isEmpty || title.isEmpty) && rawNowPlaying.isNotEmpty) {
        final separatorIndex = rawNowPlaying.indexOf(' - ');
        if (separatorIndex >= 0) {
          if (artist.isEmpty) {
            artist = rawNowPlaying.substring(0, separatorIndex).trim();
          }
          if (title.isEmpty) {
            title = rawNowPlaying.substring(separatorIndex + 3).trim();
          }
        } else if (title.isEmpty) {
          title = rawNowPlaying;
        }
      }

      if (artist.isEmpty) {
        artist = 'Bonbon Radio';
      }

      if (title.isEmpty) {
        title = 'Live Stream';
      }

      final String cover = _resolveCover(
        album: album,
        artist: artist,
        title: title,
      );

      final bool changed = force ||
          title != _lastTitle ||
          artist != _lastArtist ||
          album != _lastAlbum ||
          cover != _lastCover;

      if (!changed) return;

      _lastTitle = title;
      _lastArtist = artist;
      _lastAlbum = album;
      _lastCover = cover;

      final item = _buildMediaItem(
        album: album,
        title: title,
        artist: artist,
        cover: cover,
      );

      _publishMediaItem(item);
      _broadcastState();
    } catch (e, st) {
      developer.log(
        'refreshMetadata failed',
        name: 'BonbonAudioHandler',
        error: e,
        stackTrace: st,
      );
    }
  }

  void _startMetadataTimer() {
    _stopMetadataTimer();

    _metadataTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!_player.playing) return;
      await refreshMetadata();
    });
  }

  void _stopMetadataTimer() {
    _metadataTimer?.cancel();
    _metadataTimer = null;
  }

  @override
  Future<void> play() async {
    final url = _requestedUrl;
    if (url == null || url.isEmpty) return;

    await _startPlayback(url);
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _broadcastState();
  }

  @override
  Future<void> stop() async {
    _stopMetadataTimer();
    await _player.stop();
    _preparedUrl = null;
    _broadcastState();
  }

  @override
  Future<void> onTaskRemoved() async {
    if (!_player.playing) {
      await stop();
    }
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'retry_stream') {
      final url = _requestedUrl;
      if (url != null && url.isNotEmpty) {
        await _startPlayback(url);
      }
    }
  }

  Future<void> disposeHandler() async {
    _stopMetadataTimer();
    await _player.dispose();
  }
}