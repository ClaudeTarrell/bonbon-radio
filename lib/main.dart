import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'bonbon_audio_handler.dart';

const String kAppDataUrl =
    'https://bonbonradio.net/wp-json/bonbonradio/v1/app-data?v=20260325';

const String kFixedLogoUrl =
    'https://bonbonradio.net/wp-content/uploads/2026/03/cropped-BonBon_Radio-Logo_Homepage.png';

const String kHeaderLogoUrl =
    'https://bonbonradio.net/wp-content/uploads/2026/03/BonBon_Radio-Logo_Homepage.png';

const String kHeaderLogoFallbackUrl =
    'https://bonbonradio.net/wp-content/uploads/2026/03/cropped-BonBon_Radio-Logo_Homepage.png';

const String kFixedStreamUrl = 'https://radio.bonbonradio.net/stream';

const String kInstagramUrl =
    'https://www.instagram.com/bonbon_recordings/';
const String kFacebookUrl =
    'https://www.facebook.com/BonBonRecordings';
const String kBonbonRecUrl = 'https://bonbonrec.ch/';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  final audioHandler = await AudioService.init(
    builder: () => BonbonAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.bonbonradio.app.channel.audio',
      androidNotificationChannelName: 'Bonbon Radio Playback',
      androidStopForegroundOnPause: false,
    ),
  );

  runApp(BonbonRadioApp(audioHandler: audioHandler as BonbonAudioHandler));
}

class BonbonRadioApp extends StatelessWidget {
  final BonbonAudioHandler audioHandler;

  const BonbonRadioApp({super.key, required this.audioHandler});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bonbon Radio',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF171717),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: HomePage(audioHandler: audioHandler),
    );
  }
}

class HomePage extends StatefulWidget {
  final BonbonAudioHandler audioHandler;

  const HomePage({super.key, required this.audioHandler});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<Map<String, dynamic>> data;

  bool isPlaying = false;
  bool isLoading = false;
  bool _tapLoading = false;

  String nowTitle = '';
  String nowArtist = '';
  String nowCover = '';

  Timer? timer;
  StreamSubscription<PlaybackState>? _playbackSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;

  @override
  void initState() {
    super.initState();
    data = loadData();

    widget.audioHandler.refreshMetadata(force: true);

    _playbackSub = widget.audioHandler.playbackState.listen((state) {
      if (!mounted) return;

      final isActuallyLoading = !state.playing &&
          (state.processingState == AudioProcessingState.loading ||
              state.processingState == AudioProcessingState.buffering);

      if (state.playing && _tapLoading) {
        _tapLoading = false;
      }

      setState(() {
        isPlaying = state.playing;
        isLoading = _tapLoading || isActuallyLoading;
      });
    });

    _mediaItemSub = widget.audioHandler.mediaItem.listen((item) {
      if (!mounted || item == null) return;

      final incomingTitle = item.title.trim();
      final incomingArtist = (item.artist ?? '').trim();
      final incomingAlbum = (item.album ?? '').trim();
      final incomingCover = item.artUri?.toString().trim() ?? '';

      final isJingle = _isJingleAlbum(incomingAlbum);

      setState(() {
        if (isJingle) {
          nowTitle = '';
          nowArtist = '';
          nowCover = '';
        } else {
          nowTitle = incomingTitle;
          nowArtist = incomingArtist;
          nowCover = incomingCover;
        }
      });
    });

    timer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await widget.audioHandler.refreshMetadata();
    });
  }

  bool _isJingleAlbum(String album) {
    return album.trim().toLowerCase() == 'jingle';
  }

  void _showPrettyErrorSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          backgroundColor: Colors.transparent,
          duration: const Duration(seconds: 4),
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF252525),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color.fromRGBO(255, 255, 255, 0.12),
                width: 1.2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.32),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(255, 255, 255, 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color.fromRGBO(255, 255, 255, 0.10),
                    ),
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Color(0xFFF3F3F3),
                      fontSize: 14.5,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }

  Future<Map<String, dynamic>> loadData() async {
    try {
      final res = await http
          .get(
            Uri.parse(kAppDataUrl),
            headers: const {'Cache-Control': 'no-cache'},
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) {
        throw Exception('Server antwortet mit Status ${res.statusCode}');
      }

      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return {
        'appName': 'Bonbon Radio',
        'tagline': 'From Zurich to the World',
        'description':
            'Bonbon Radio is an independent electronic music station based in Zurich, powered by Bonbon Recordings.',
        'websiteUrl': 'https://bonbonradio.net',
        'program': [],
      };
    }
  }

  Future<void> togglePlay(String url) async {
    if (_tapLoading) return;

    try {
      if (isPlaying) {
        await widget.audioHandler.stop();
        if (!mounted) return;
        setState(() {
          isPlaying = false;
          isLoading = false;
          _tapLoading = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _tapLoading = true;
        isLoading = true;
      });

      await widget.audioHandler.playStream(
        url,
        fallbackTitle: nowTitle.isNotEmpty ? nowTitle : 'Live Stream',
        fallbackArtist: nowArtist.isNotEmpty ? nowArtist : 'Bonbon Radio',
        fallbackCover: nowCover.isNotEmpty ? nowCover : kFixedLogoUrl,
      );

      if (!mounted) return;
      setState(() {
        _tapLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isPlaying = false;
        isLoading = false;
        _tapLoading = false;
      });

      _showPrettyErrorSnackBar('Stream konnte nicht gestartet werden.');
    }
  }

  Future<void> openLink(String url) async {
    final uri = Uri.parse(url);

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      _showPrettyErrorSnackBar('Link konnte nicht geöffnet werden.');
    }
  }

  String _normalizeTime(String time) {
    final value = time.trim();
    if (value.isEmpty) return '00:00';
    if (value == '24:00') return '24:00';

    final parts = value.split(':');
    final hh = parts.isNotEmpty ? parts[0].padLeft(2, '0') : '00';
    final mm = parts.length > 1 ? parts[1].padLeft(2, '0') : '00';
    return '$hh:$mm';
  }

  String _buildScheduleText(String start, String end) {
    return '${_normalizeTime(start)}-${_normalizeTime(end)} CET/CEST';
  }

  String _todayName() {
    final weekday = DateTime.now().weekday;
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[weekday - 1];
  }

  bool _isCurrentShow(String start, String end) {
    try {
      final now = DateTime.now();
      final currentMinutes = now.hour * 60 + now.minute;

      int parseMinutes(String time) {
        final normalized = _normalizeTime(time);
        if (normalized == '24:00') return 24 * 60;
        final parts = normalized.split(':');
        final hh = int.tryParse(parts[0]) ?? 0;
        final mm = int.tryParse(parts[1]) ?? 0;
        return hh * 60 + mm;
      }

      final startMinutes = parseMinutes(start);
      final endMinutes = parseMinutes(end);

      if (endMinutes == 24 * 60) {
        return currentMinutes >= startMinutes && currentMinutes < endMinutes;
      }

      if (endMinutes < startMinutes) {
        return currentMinutes >= startMinutes || currentMinutes < endMinutes;
      }

      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    _playbackSub?.cancel();
    _mediaItemSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Map<String, dynamic>>(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final json = snapshot.data ??
              {
                'appName': 'Bonbon Radio',
                'tagline': 'From Zurich to the World',
                'description':
                    'Bonbon Radio is an independent electronic music station based in Zurich, powered by Bonbon Recordings.',
                'websiteUrl': 'https://bonbonradio.net',
                'program': [],
              };

          final appName = (json['appName'] ?? 'Bonbon Radio').toString();
          final tagline =
              (json['tagline'] ?? 'From Zurich to the World').toString();
          final description = (json['description'] ?? '').toString();
          final streamUrl = kFixedStreamUrl;
          final websiteUrl = (json['websiteUrl'] ?? '').toString();
          final program = (json['program'] as List?) ?? [];
          final today = _todayName();

          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF1B1B1B),
                  Color(0xFF131313),
                  Color(0xFF0D0D0D),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: RefreshIndicator(
                onRefresh: () async {
                  await widget.audioHandler.refreshMetadata(force: true);
                  setState(() {
                    data = loadData();
                  });
                  await data;
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
                  children: [
                    _NowPlayingHero(
                      coverUrl: nowCover,
                      artist: nowArtist,
                      title: nowTitle,
                      headerLogoUrl: kHeaderLogoUrl,
                      appName: appName,
                      tagline: tagline,
                    ),
                    const SizedBox(height: 18),
                    _PlayerButton(
                      isPlaying: isPlaying,
                      isLoading: isLoading,
                      onTap:
                          streamUrl.isEmpty ? null : () => togglePlay(streamUrl),
                    ),
                    const SizedBox(height: 22),
                    _InfoCard(
                      title: 'About',
                      child: Text(
                        description,
                        style: const TextStyle(
                          color: Color(0xFFF0F0F0),
                          fontSize: 16,
                          height: 1.6,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Programm',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ...program.map((day) {
                      final dayMap = day as Map<String, dynamic>;
                      final rawShows = (dayMap['shows'] as List?) ?? [];
                      final shows = rawShows
                          .map((e) => Map<String, dynamic>.from(e as Map))
                          .toList();

                      final dayName = (dayMap['day'] ?? '').toString();
                      final isToday =
                          dayName.toLowerCase() == today.toLowerCase();

                      return _ProgramCard(
                        day: dayName,
                        shows: shows,
                        isToday: isToday,
                        buildScheduleText: _buildScheduleText,
                        isCurrentShow: _isCurrentShow,
                      );
                    }),
                    const SizedBox(height: 24),
                    const Text(
                      'Follow us',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _SocialButton(
                          icon: Icons.camera_alt_rounded,
                          label: 'Instagram',
                          onTap: () => openLink(kInstagramUrl),
                        ),
                        _SocialButton(
                          icon: Icons.facebook_rounded,
                          label: 'Facebook',
                          onTap: () => openLink(kFacebookUrl),
                        ),
                        if (websiteUrl.isNotEmpty)
                          _SocialButton(
                            icon: Icons.language_rounded,
                            label: 'Website',
                            onTap: () => openLink(websiteUrl),
                          ),
                        _SocialButton(
                          icon: Icons.public_rounded,
                          label: 'Bonbon Rec',
                          onTap: () => openLink(kBonbonRecUrl),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BonbonRadioWordmark extends StatelessWidget {
  final double fontSize;
  final Color color;
  final TextAlign textAlign;

  const _BonbonRadioWordmark({
    required this.fontSize,
    this.color = Colors.white,
    this.textAlign = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          TextSpan(
            text: 'BONBON',
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              height: 1.0,
              letterSpacing: 0,
            ),
          ),
          TextSpan(
            text: 'RADIO',
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w100,
              height: 1.0,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _NowPlayingHero extends StatelessWidget {
  final String coverUrl;
  final String artist;
  final String title;
  final String headerLogoUrl;
  final String appName;
  final String tagline;

  const _NowPlayingHero({
    required this.coverUrl,
    required this.artist,
    required this.title,
    required this.headerLogoUrl,
    required this.appName,
    required this.tagline,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(30);
    final hasCover = coverUrl.trim().isNotEmpty;
    const bgColor = Color(0xFF171717);

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: const Color.fromRGBO(255, 255, 255, 0.10),
          width: 1.3,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.38),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: SizedBox(
        height: 455,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bgColor,
            image: hasCover
                ? DecorationImage(
                    image: NetworkImage(coverUrl),
                    fit: BoxFit.cover,
                    onError: (_, __) {},
                  )
                : null,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.fromRGBO(0, 0, 0, 0.10),
                    Color.fromRGBO(0, 0, 0, 0.24),
                    Color.fromRGBO(0, 0, 0, 0.68),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BrandHeader(
                      headerLogoUrl: headerLogoUrl,
                      appName: appName,
                      tagline: tagline,
                    ),
                    const Spacer(),
                    const Text(
                      'NOW PLAYING',
                      style: TextStyle(
                        color: Color(0xFFE0E0E0),
                        fontSize: 12,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (title.isEmpty)
                      const _BonbonRadioWordmark(fontSize: 31)
                    else
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 31,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      artist.isEmpty ? tagline : artist,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE0E0E0),
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  final String headerLogoUrl;
  final String appName;
  final String tagline;

  const _BrandHeader({
    required this.headerLogoUrl,
    required this.appName,
    required this.tagline,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 58,
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color.fromRGBO(255, 255, 255, 0.22),
              width: 1.5,
            ),
          ),
          child: _LogoImage(logoUrl: headerLogoUrl),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const _BonbonRadioWordmark(fontSize: 26),
                const SizedBox(height: 4),
                Text(
                  tagline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE0E0E0),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LogoImage extends StatelessWidget {
  final String logoUrl;

  const _LogoImage({required this.logoUrl});

  @override
  Widget build(BuildContext context) {
    final resolvedUrl =
        logoUrl.trim().isNotEmpty ? logoUrl.trim() : kHeaderLogoUrl;

    return SizedBox(
      width: 42,
      height: 42,
      child: Image.network(
        resolvedUrl,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          return child;
        },
        errorBuilder: (_, __, ___) {
          return Image.network(
            kHeaderLogoFallbackUrl,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) {
              return const Icon(
                Icons.radio_rounded,
                color: Colors.white,
                size: 30,
              );
            },
          );
        },
      ),
    );
  }
}

class _PlayerButton extends StatelessWidget {
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback? onTap;

  const _PlayerButton({
    required this.isPlaying,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF2E2E2E),
                Color(0xFF242424),
              ],
            ),
            border: Border.all(color: Colors.white10),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 14,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE0E0E0),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    color: Colors.black,
                    size: 26,
                  ),
                ),
              const SizedBox(width: 14),
              Text(
                isLoading
                    ? 'Lädt Stream...'
                    : isPlaying
                        ? 'Stop Live Stream'
                        : 'Play Live Stream',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _InfoCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ProgramCard extends StatelessWidget {
  final String day;
  final List<Map<String, dynamic>> shows;
  final bool isToday;
  final String Function(String start, String end) buildScheduleText;
  final bool Function(String start, String end) isCurrentShow;

  const _ProgramCard({
    required this.day,
    required this.shows,
    required this.isToday,
    required this.buildScheduleText,
    required this.isCurrentShow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isToday ? const Color(0xFF2A2A2A) : const Color(0xFF202020),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isToday ? Colors.white24 : Colors.white10,
          width: isToday ? 1.3 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: isToday,
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          collapsedIconColor: Colors.white,
          iconColor: const Color(0xFFE0E0E0),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  day,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (isToday)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Text(
                    'TODAY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
            ],
          ),
          children: shows.map((show) {
            final subtitle = (show['subtitle'] ?? '').toString().trim();
            final start = (show['start'] ?? '').toString();
            final end = (show['end'] ?? '').toString();
            final schedule = buildScheduleText(start, end);
            final live = isToday && isCurrentShow(start, end);

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: live ? const Color(0xFF303030) : const Color(0xFF181818),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: live ? Colors.white24 : Colors.white10,
                  width: live ? 1.3 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (live) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'LIVE NOW',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    (show['title'] ?? '').toString(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: live ? 18 : 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    schedule,
                    style: TextStyle(
                      color: live ? Colors.white : const Color(0xFFE0E0E0),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SocialButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF222222),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFFE0E0E0), size: 22),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}