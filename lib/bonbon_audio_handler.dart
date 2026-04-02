import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

const String kNowPlayingUrl =
    'https://radio.bonbonradio.net/json/stream/bonbonradio';
const String kFixedLogoUrl =
    'https://bonbonradio.net/wp-content/uploads/2026/03/cropped-BonBon_Radio-Logo_Homepage.png';

class BonbonAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  Timer? _metadataTimer;
  String _currentStreamUrl = '';
  bool _sourcePrepared = false;

  String _lastTitle = '';
  String _lastArtist = '';
  String _lastCover = '';
  String _lastAlbum = '';

  BonbonAudioHandler() {
    _player.playbackEventStream.listen(
      (_) => _broadcastState(),
      onError: (Object error, StackTrace stackTrace) {
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            playing: false,
          ),
        );
      },
    );
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

  bool _isImageUrl(String value) {
    final lower = value.trim().toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  String _cleanUrl(String value) {
    return value.replaceAll(r'\/', '/').trim();
  }

  String _normalizeHost(String value) {
    var cleaned = _cleanUrl(value);

    if (cleaned.startsWith('http://178.104.138.250:2020')) {
      cleaned = cleaned.replaceFirst(
        'http://178.104.138.250:2020',
        'https://radio.bonbonradio.net',
      );
    }

    return cleaned;
  }

  String _resolveBestCover(Map<String, dynamic> json) {
    final urlField = _normalizeHost((json['url'] ?? '').toString());
    final coverField = _normalizeHost((json['cover'] ?? '').toString());
    final artField = _normalizeHost((json['art'] ?? '').toString());
    final coverArtField = _normalizeHost((json['coverart'] ?? '').toString());

    if (urlField.isNotEmpty && _isImageUrl(urlField)) {
      return urlField;
    }

    if (coverField.isNotEmpty && _isImageUrl(coverField)) {
      return coverField;
    }

    if (artField.isNotEmpty && _isImageUrl(artField)) {
      return artField;
    }

    if (coverArtField.isNotEmpty) {
      return coverArtField;
    }

    final covers = json['covers'];
    if (covers is List && covers.isNotEmpty) {
      final first = _normalizeHost(covers.first.toString());
      if (first.isNotEmpty) {
        return first;
      }
    }

    final nowPlaying = json['now_playing'];
    if (nowPlaying is Map<String, dynamic>) {
      final songMap = nowPlaying['song'];
      if (songMap is Map<String, dynamic>) {
        final songArt = _normalizeHost((songMap['art'] ?? '').toString());
        if (songArt.isNotEmpty) {
          return songArt;
        }
      }
    }

    final song = json['song'];
    if (song is Map<String, dynamic>) {
      final songArt = _normalizeHost((song['art'] ?? '').toString());
      if (songArt.isNotEmpty) {
        return songArt;
      }
    }

    return kFixedLogoUrl;
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

    return 'Bonbon Radio';
  }

  Uri _safeArtUri(String cover) {
    final value = cover.trim();
    if (value.isEmpty) return Uri.parse(kFixedLogoUrl);

    final parsed = Uri.tryParse(value);
    if (parsed == null || !parsed.hasScheme) {
      return Uri.parse(kFixedLogoUrl);
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

    if (!_sourcePrepared ||
        _currentStreamUrl != url ||
        _player.processingState == ProcessingState.idle) {
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.loading,
          playing: false,
        ),
      );

      await _player.setAudioSource(
        AudioSource.uri(Uri.parse(url)),
        preload: true,
      );

      _currentStreamUrl = url;
      _sourcePrepared = true;
    }

    await _player.play();
    _startMetadataTimer();
    await refreshMetadata(force: true);
    _broadcastState();
  }

  Future<void> refreshMetadata({bool force = false}) async {
    try {
      final res = await http.get(
        Uri.parse(kNowPlayingUrl),
        headers: const {'Cache-Control': 'no-cache'},
      );

      if (res.statusCode != 200) return;

      final json = jsonDecode(res.body) as Map<String, dynamic>;

      final rawNowPlaying = (json['nowplaying'] ?? '').toString().trim();

      String title = '';
      String artist = '';
      final String album = _resolveAlbum(json);
      final String cover = _resolveBestCover(json);

      if (rawNowPlaying.isNotEmpty) {
        final separatorIndex = rawNowPlaying.indexOf(' - ');
        if (separatorIndex >= 0) {
          artist = rawNowPlaying.substring(0, separatorIndex).trim();
          title = rawNowPlaying.substring(separatorIndex + 3).trim();
        } else {
          title = rawNowPlaying;
        }
      }

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
    } catch (_) {}
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

    if (!_sourcePrepared || _player.processingState == ProcessingState.idle) {
      await _player.setAudioSource(
        AudioSource.uri(Uri.parse(_currentStreamUrl)),
        preload: true,
      );
      _sourcePrepared = true;
    }

    await _player.play();
    _startMetadataTimer();
    await refreshMetadata(force: true);
    _broadcastState();
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
}