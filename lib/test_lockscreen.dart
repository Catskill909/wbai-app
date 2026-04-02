import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// A dedicated test file to debug iOS lockscreen metadata issues
/// This bypasses all other app code to focus solely on the lockscreen problem
void main() {
  runApp(const LockscreenTestApp());
}

class LockscreenTestApp extends StatelessWidget {
  const LockscreenTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iOS Lockscreen Test',
      theme: ThemeData(
        primarySwatch: Colors.red,
        useMaterial3: true,
      ),
      home: const LockscreenTestScreen(),
    );
  }
}

class LockscreenTestScreen extends StatefulWidget {
  const LockscreenTestScreen({super.key});

  @override
  State<LockscreenTestScreen> createState() => _LockscreenTestScreenState();
}

class _LockscreenTestScreenState extends State<LockscreenTestScreen> {
  final TextEditingController _titleController =
      TextEditingController(text: 'Community Watch & Comment');
  final TextEditingController _artistController =
      TextEditingController(text: 'Host: David Rabin');
  final TextEditingController _albumController =
      TextEditingController(text: 'WBAI 99.5 FM');

  // Direct native channel - CRITICAL: Must match AppDelegate.swift
  static const MethodChannel _channel =
      MethodChannel('com.wbaifm.radio/now_playing');

  // Audio player - CRITICAL: iOS requires actual audio playback for lockscreen metadata
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  String _status = 'Ready to test';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      // Initialize audio source with WBAI stream URL
      await _player.setUrl('https://streaming.wbai.org/wbai_verizon');
      setState(() => _status = 'Audio initialized');
    } catch (e) {
      setState(() => _status = 'Error initializing audio: $e');
    }
  }

  Future<void> _togglePlayback() async {
    setState(() => _isLoading = true);

    try {
      if (_isPlaying) {
        await _player.pause();
        setState(() {
          _isPlaying = false;
          _status = 'Audio paused';
        });
      } else {
        await _player.play();
        setState(() {
          _isPlaying = true;
          _status = 'Audio playing';
        });

        // Update lockscreen metadata after playback starts
        await Future.delayed(const Duration(milliseconds: 500));
        _updateLockscreen();
      }
    } catch (e) {
      setState(() => _status = 'Error toggling playback: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _player.dispose();
    super.dispose();
  }

  // Clear the lockscreen metadata
  Future<void> _clearLockscreen() async {
    if (!Platform.isIOS) {
      setState(() => _status = 'This test only works on iOS devices');
      return;
    }

    setState(() {
      _status = 'Clearing lockscreen...';
      _isLoading = true;
    });

    try {
      await _channel.invokeMethod('clearNowPlaying');
      setState(() => _status = 'Lockscreen cleared successfully');
    } catch (e) {
      setState(() => _status = 'Error clearing lockscreen: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Update the lockscreen with test metadata
  Future<void> _updateLockscreen() async {
    if (!Platform.isIOS) {
      setState(() => _status = 'This test only works on iOS devices');
      return;
    }

    final title = _titleController.text;
    final artist = _artistController.text;
    final album = _albumController.text;

    if (title.isEmpty || artist.isEmpty || album.isEmpty) {
      setState(() => _status = 'Title, artist and album are required');
      return;
    }

    setState(() {
      _status = 'Updating lockscreen...';
      _isLoading = true;
    });

    try {
      // First clear any existing metadata
      await _channel.invokeMethod('clearNowPlaying');

      // Wait a moment to ensure clear takes effect
      await Future.delayed(const Duration(milliseconds: 300));

      // Create metadata map
      final Map<String, dynamic> metadata = {
        'title': title,
        'artist': artist,
        'album': album,
        'artworkUrl':
            'https://www.wbai.org/playlist/images/wbai_logo.png',
        'isPlaying': true,
      };

      // Send the update
      final result = await _channel.invokeMethod('updateNowPlaying', metadata);
      setState(() => _status = 'Lockscreen updated: $result');

      // Force a second update after a delay
      await Future.delayed(const Duration(milliseconds: 500));
      await _channel.invokeMethod('updateNowPlaying', metadata);
      setState(() => _status = 'Second update sent successfully');
    } catch (e) {
      setState(() => _status = 'Error updating lockscreen: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('iOS Lockscreen Test'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'This is a dedicated test for the iOS lockscreen metadata issue',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title (Show Name)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _artistController,
              decoration: const InputDecoration(
                labelText: 'Artist (Host)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _albumController,
              decoration: const InputDecoration(
                labelText: 'Album (Station)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _togglePlayback,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(_isPlaying ? 'PAUSE AUDIO' : 'PLAY AUDIO (REQUIRED)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading || !_isPlaying ? null : _updateLockscreen,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('UPDATE LOCKSCREEN'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _isLoading ? null : _clearLockscreen,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Clear Lockscreen'),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Status:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(_status),
                  if (_isLoading) ...[
                    const SizedBox(height: 16),
                    const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Spacer(),
            if (Platform.isIOS)
              const Text(
                'Note: Check your lockscreen after pressing the update button. '
                'You may need to lock your device to see the changes.',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              )
            else
              const Text(
                'This test only works on iOS devices.',
                style: TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}
