import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:audio_service/audio_service.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

const String kNowPlayingUrl =
    'https://radio.bonbonradio.net/json/stream/bonbonradio';

const String kFixedLogoUrl =
    'https://bonbonradio.net/wp-content/uploads/2026/03/cropped-BonBon_Radio-Logo_Homepage.png';

const String kCoverBaseUrl =
    'https://bonbonradio.net/wp-content/uploads/radio-covers/';

const String kDefaultCoverUrl = '${kCoverBaseUrl}default.jpeg';

class BonbonAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  Timer? _metadataTimer;
  String _currentStreamUrl = '';
  bool _sourcePrepared = false;

  String _lastTitle = '';
  String _lastArtist = '';
  String _lastCover = '';
  String _lastAlbum = '';

  static const Map<String, String> _streamHeaders = {
    'User-Agent': 'BonbonRadioApp/1.0 (Android)',
    'Accept': '*/*',
    'Icy-MetaData': '1',
    'Connection': 'keep-alive',
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
  };

  BonbonAudioHandler() {
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

    _player.playerStateStream.listen((_) {
      _broadcastState();
    });
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
    final playing = _player.playing;

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.play,
          MediaAction.pause,
          MediaAction.stop,
        },
        androidCompactActionIndices: const [0, 1],
        processingState: _mapProcessingState(_player.processingState),
        playing: playing,
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

  String _resolveAlbum(Map<String, dynamic> json) {
    final direct = (json['album'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    final song = json['song'];
    if (song is Map<String, dynamic>) {
      final album = (song['album'] ?? '').toString().trim();
      if (album.isNotEmpty) return album;
    }

    final nowPlaying = json['now_playing'];
    if (nowPlaying is Map<String, dynamic>) {
      final songMap = nowPlaying['song'];
      if (songMap is Map<String, dynamic>) {
        final album = (songMap['album'] ?? '').toString().trim();
        if (album.isNotEmpty) return album;
      }
    }

    final nowPlayingData = json['nowplaying_data'];
    if (nowPlayingData is Map<String, dynamic>) {
      final songMap = nowPlayingData['song'];
      if (songMap is Map<String, dynamic>) {
        final album = (songMap['album'] ?? '').toString().trim();
        if (album.isNotEmpty) return album;
      }
    }

    final currentTrack = json['currenttrack'];
    if (currentTrack is Map<String, dynamic>) {
      final album = (currentTrack['album'] ?? '').toString().trim();
      if (album.isNotEmpty) return album;
    }

    return '';
  }

  String _resolveArtistFromJson(Map<String, dynamic> json) {
    final direct = (json['artist'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    final song = json['song'];
    if (song is Map<String, dynamic>) {
      final artist = (song['artist'] ?? '').toString().trim();
      if (artist.isNotEmpty) return artist;
    }

    final nowPlaying = json['now_playing'];
    if (nowPlaying is Map<String, dynamic>) {
      final songMap = nowPlaying['song'];
      if (songMap is Map<String, dynamic>) {
        final artist = (songMap['artist'] ?? '').toString().trim();
        if (artist.isNotEmpty) return artist;
      }
    }

    final nowPlayingData = json['nowplaying_data'];
    if (nowPlayingData is Map<String, dynamic>) {
      final songMap = nowPlayingData['song'];
      if (songMap is Map<String, dynamic>) {
        final artist = (songMap['artist'] ?? '').toString().trim();
        if (artist.isNotEmpty) return artist;
      }
    }

    final currentTrack = json['currenttrack'];
    if (currentTrack is Map<String, dynamic>) {
      final artist = (currentTrack['artist'] ?? '').toString().trim();
      if (artist.isNotEmpty) return artist;
    }

    return '';
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
    return MediaItem(
      id: 'bonbonradio-live',
      album: album.isNotEmpty ? album : 'Bonbon Radio',
      title: title.isNotEmpty ? title : 'Live Stream',
      artist: artist.isNotEmpty ? artist : 'Bonbon Radio',
      artUri: _safeArtUri(cover),
    );
  }

  Future<void> _prepareSource(String url) async {
    final uri = Uri.parse(url);

    await _player.stop();

    await _player.setAudioSource(
      AudioSource.uri(
        uri,
        headers: _streamHeaders,
      ),
      preload: true,
    );

    _currentStreamUrl = url;
    _sourcePrepared = true;
  }

  Future<void> playStream(
    String url, {
    required String fallbackTitle,
    required String fallbackArtist,
    required String fallbackCover,
  }) async {
    mediaItem.add(
      _buildMediaItem(
        album: 'Bonbon Radio',
        title: fallbackTitle,
        artist: fallbackArtist,
        cover: fallbackCover,
      ),
    );

    try {
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.loading,
          playing: false,
        ),
      );

      final shouldReprepare = !_sourcePrepared ||
          _currentStreamUrl != url ||
          _player.processingState == ProcessingState.idle;

      if (shouldReprepare) {
        await _prepareSource(url).timeout(const Duration(seconds: 20));
      }

      await _player.play().timeout(const Duration(seconds: 20));

      _startMetadataTimer();
      await refreshMetadata(force: true);
      _broadcastState();
    } catch (e, st) {
      developer.log(
        'playStream failed',
        name: 'BonbonAudioHandler',
        error: e,
        stackTrace: st,
      );

      _sourcePrepared = false;

      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          playing: false,
        ),
      );

      rethrow;
    }
  }

  Future<void> refreshMetadata({bool force = false}) async {
    try {
      final res = await http.get(
        Uri.parse(kNowPlayingUrl),
        headers: const {
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
          'User-Agent': 'BonbonRadioApp/1.0 (Android)',
        },
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) return;

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final rawNowPlaying = (json['nowplaying'] ?? '').toString().trim();

      String title = '';
      String artist = '';
      final String album = _resolveAlbum(json);

      if (rawNowPlaying.isNotEmpty) {
        final separatorIndex = rawNowPlaying.indexOf(' - ');
        if (separatorIndex >= 0) {
          artist = rawNowPlaying.substring(0, separatorIndex).trim();
          title = rawNowPlaying.substring(separatorIndex + 3).trim();
        } else {
          title = rawNowPlaying;
        }
      }

      if (artist.isEmpty) {
        artist = _resolveArtistFromJson(json);
      }

      final String cover = _resolveCover(
        album: album,
        artist: artist,
        title: title,
      );

      final changed = force ||
          title != _lastTitle ||
          artist != _lastArtist ||
          cover != _lastCover ||
          album != _lastAlbum;

      if (!changed) return;

      _lastTitle = title;
      _lastArtist = artist;
      _lastCover = cover;
      _lastAlbum = album;

      mediaItem.add(
        _buildMediaItem(
          album: album,
          title: title,
          artist: artist,
          cover: cover,
        ),
      );
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
    _metadataTimer?.cancel();
    _metadataTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await refreshMetadata();
    });
  }

  void _stopMetadataTimer() {
    _metadataTimer?.cancel();
    _metadataTimer = null;
  }

  @override
  Future<void> play() async {
    if (_currentStreamUrl.isEmpty) return;

    try {
      if (!_sourcePrepared || _player.processingState == ProcessingState.idle) {
        await _prepareSource(_currentStreamUrl)
            .timeout(const Duration(seconds: 20));
      }

      await _player.play().timeout(const Duration(seconds: 20));
      _startMetadataTimer();
      await refreshMetadata(force: true);
      _broadcastState();
    } catch (e, st) {
      developer.log(
        'play failed',
        name: 'BonbonAudioHandler',
        error: e,
        stackTrace: st,
      );

      _sourcePrepared = false;

      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          playing: false,
        ),
      );

      rethrow;
    }
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _stopMetadataTimer();
    _broadcastState();
  }

  @override
  Future<void> stop() async {
    _stopMetadataTimer();
    await _player.stop();
    _sourcePrepared = false;
    _broadcastState();
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'retry_stream' && _currentStreamUrl.isNotEmpty) {
      await play();
    }
  }
}