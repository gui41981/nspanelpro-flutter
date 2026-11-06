import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'env.dart';

/// Native HLS camera renderer. The stream URL is created by Home Assistant
/// over the already-authenticated WebSocket connection; the short-lived HLS
/// token is embedded in that URL, so no camera credentials are stored here.
class CameraLiveView extends StatefulWidget {
  const CameraLiveView({
    super.key,
    required this.entityId,
    required this.env,
    this.ptz = const {},
  });

  final String entityId;
  final PanelEnv env;
  final Map<String, dynamic> ptz;

  @override
  State<CameraLiveView> createState() => _CameraLiveViewState();
}

class _CameraLiveViewState extends State<CameraLiveView> {
  VideoPlayerController? _player;
  String? _error;
  bool _loading = true;
  bool _ptzBusy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _openStream();
  }

  @override
  void didUpdateWidget(covariant CameraLiveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entityId != widget.entityId ||
        oldWidget.env.settings.url != widget.env.settings.url ||
        oldWidget.env.conn.generation != widget.env.conn.generation) {
      _openStream();
    }
  }

  bool _isCurrent(int generation) =>
      mounted && generation == _generation;

  Uri _streamUri(String path) {
    final parsed = Uri.tryParse(path);
    if (parsed != null && parsed.hasScheme) return parsed;
    return Uri.parse(widget.env.settings.resolve(path));
  }

  Future<void> _openStream() async {
    final generation = ++_generation;
    final previous = _player;
    _player = null;
    if (previous != null) {
      await previous.dispose();
    }
    if (!_isCurrent(generation)) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final path = await widget.env.conn.fetchCameraStream(widget.entityId);
      if (!_isCurrent(generation)) return;

      final controller = VideoPlayerController.networkUrl(_streamUri(path));
      _player = controller;
      await controller.initialize();
      if (!_isCurrent(generation)) {
        await controller.dispose();
        return;
      }

      await controller.setLooping(false);
      await controller.play();
      if (!_isCurrent(generation)) return;

      setState(() => _loading = false);
    } catch (error) {
      if (!_isCurrent(generation)) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _ptz(String key) async {
    final entityId = widget.ptz[key]?.toString();
    if (entityId == null || !entityId.startsWith('button.')) return;
    if (_ptzBusy) return;

    setState(() => _ptzBusy = true);
    try {
      final ok = await widget.env.conn.callService(
        'button',
        'press',
        {'entity_id': entityId},
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Commande PTZ impossible : $entityId')),
        );
      }
    } finally {
      if (mounted) setState(() => _ptzBusy = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    final player = _player;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  Widget _ptzButton(String key, IconData icon, String tooltip) {
    if (widget.ptz[key] == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: tooltip,
      onPressed: _ptzBusy ? null : () => _ptz(key),
      icon: Icon(icon, color: Colors.white),
      style: IconButton.styleFrom(
        backgroundColor: Colors.black54,
        disabledBackgroundColor: Colors.black26,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (player != null && player.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: player.value.aspectRatio,
                child: VideoPlayer(player),
              ),
            ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off, color: Colors.white70, size: 36),
                    const SizedBox(height: 10),
                    Text(
                      'Flux indisponible\n$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _openStream,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            ),
          if (widget.ptz.isNotEmpty)
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ptzButton('left', Icons.chevron_left, 'Gauche'),
                  _ptzButton('up', Icons.keyboard_arrow_up, 'Haut'),
                  _ptzButton('stop', Icons.stop_circle_outlined, 'Arrêter'),
                  _ptzButton('down', Icons.keyboard_arrow_down, 'Bas'),
                  _ptzButton('right', Icons.chevron_right, 'Droite'),
                  _ptzButton('calibrate', Icons.center_focus_strong, 'Calibrer'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
