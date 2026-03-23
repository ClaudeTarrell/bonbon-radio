import 'package:flutter/material.dart';
import 'dart:html' as html;

void main() {
  runApp(const BonbonRadioApp());
}

class BonbonRadioApp extends StatelessWidget {
  const BonbonRadioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bonbon Radio',
      debugShowCheckedModeBanner: false,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final html.AudioElement player = html.AudioElement();
  bool isPlaying = false;

  final String streamUrl =
      'https://radio.bonbonradio.net/listen/bonbonradio/radio.mp3';

  @override
  void initState() {
    super.initState();
    player.src = streamUrl;
  }

  void togglePlay() {
    if (isPlaying) {
      player.pause();
    } else {
      player.play();
    }

    setState(() {
      isPlaying = !isPlaying;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bonbon Radio'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.radio, size: 100),
            const SizedBox(height: 20),
            const Text(
              'Bonbon Radio',
              style: TextStyle(fontSize: 28),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: togglePlay,
              child: Text(isPlaying ? 'Stop' : 'Play'),
            ),
          ],
        ),
      ),
    );
  }
}