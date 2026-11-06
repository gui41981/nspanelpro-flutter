import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/dashboard.dart';
import 'camera_live_view.dart';
import 'env.dart';

/// Generic renderer for Lovelace camera cards.
///
/// The camera entity and display mode always come from the card configuration.
class CameraCard extends StatefulWidget {
  const CameraCard({super.key, required this.config, required this.env});

  final CardConfig config;
  final PanelEnv env;

  static bool supports(CardConfig config) {
    final type = _type(config);
    final entity = _cameraEntity(config['entity']);
    final cameraImage = _string(config['camera_image']);
    final image = _string(config['image']);

    if (type == 'nspanel-camera-card') {
      return true;
    }

    if (type == 'picture-entity') {
      return entity != null;
    }

    if (type == 'picture-glance') {
      return _cameraEntity(cameraImage) != null ||
          entity != null ||
          _isUrl(cameraImage) ||
          _isRelativePath(cameraImage);
    }

    return type == 'picture' && (_isUrl(image) || _isRelativePath(image));
  }

  static String _type(CardConfig config) =>
      (config['type']?.toString() ?? '').replaceFirst(RegExp(r'^custom:'), '');

  static String? _string(dynamic value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  static String? _cameraEntity(dynamic value) {
    final id = value is Map ? _string(value['entity']) : _string(value);
    return id != null && id.startsWith('camera.') ? id : null;
  }

  static bool _isUrl(String? value) {
    if (value == null) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static bool _isRelativePath(String? value) =>
      value != null && value.startsWith('/');

  @override
  State<CameraCard> createState() => _CameraCardState();
}

class _CameraCardState extends State<CameraCard> {
  late final WebViewController _controller;

  int _generation = 0;
  int _progress = 0;
  String? _error;

  String? get _entity {
    final config = widget.config;
    final type = CameraCard._type(config);
    // camera_image has precedence when explicitly configured.
    final cameraImage = CameraCard._string(config['camera_image']);
    final imageEntity = CameraCard._cameraEntity(cameraImage);
    if (imageEntity != null) return imageEntity;

    // An explicitly configured image URL/path takes precedence over entity.
    if (cameraImage != null) return null;

    final entity = CameraCard._cameraEntity(config['entity']);
    if (entity != null) return entity;

    if (type == 'nspanel-camera-card') {
      return null;
    }

    return null;
  }

  String? get _imageUrl {
    final config = widget.config;
    final type = CameraCard._type(config);

    final cameraImage = CameraCard._string(config['camera_image']);
    if (cameraImage != null && CameraCard._cameraEntity(cameraImage) == null) {
      return cameraImage;
    }

    if (type == 'picture' || type == 'nspanel-camera-card') {
      return CameraCard._string(config['image']) ??
          CameraCard._string(config['url']);
    }

    return null;
  }

  bool get _isLive =>
      widget.config['camera_view']?.toString().toLowerCase() == 'live';

  bool get _hasSource => _entity != null || _imageUrl != null;

  bool get _isNativeLive => _isLive && _entity != null;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    if (!_isNativeLive) _loadSource();
  }

  @override
  void didUpdateWidget(covariant CameraCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.config.toString() != widget.config.toString() ||
        oldWidget.env.settings.url != widget.env.settings.url ||
        oldWidget.env.settings.token != widget.env.settings.token) {
      if (!_isNativeLive) _loadSource();
    }
  }

  bool _isCurrent(int generation) => mounted && generation == _generation;

  Future<void> _loadSource() async {
    if (_isNativeLive) return;
    final generation = ++_generation;

    if (mounted) {
      setState(() {
        _progress = 0;
        _error = null;
      });
    }

    if (!_hasSource) {
      if (!_isCurrent(generation)) return;
      setState(() {
        _error = 'Aucune source configurée pour cette carte caméra.';
        _progress = 100;
      });
      return;
    }

    try {
      await _controller.setJavaScriptMode(JavaScriptMode.disabled);
      if (!_isCurrent(generation)) return;

      await _controller.setBackgroundColor(Colors.black);
      if (!_isCurrent(generation)) return;

      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!_isCurrent(generation)) return;
            setState(() => _progress = progress);
          },
          onPageStarted: (_) {
            if (!_isCurrent(generation)) return;
            setState(() {
              _progress = 0;
              _error = null;
            });
          },
          onPageFinished: (_) {
            if (!_isCurrent(generation)) return;
            setState(() => _progress = 100);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true || !_isCurrent(generation)) {
              return;
            }

            setState(() {
              _error = error.description;
              _progress = 100;
            });
          },
        ),
      );
      if (!_isCurrent(generation)) return;

      final entity = _entity;
      late final Uri uri;
      var isApiRequest = false;

      if (entity != null) {
        final endpoint = _isLive
            ? '/api/camera_proxy_stream/${Uri.encodeComponent(entity)}'
            : '/api/camera_proxy/${Uri.encodeComponent(entity)}';

        uri = Uri.parse(widget.env.settings.resolve(endpoint));
        isApiRequest = true;
      } else {
        final source = _imageUrl!;
        uri = Uri.parse(
          CameraCard._isUrl(source)
              ? source
              : widget.env.settings.resolve(source),
        );

        isApiRequest = uri.path.startsWith('/api/');
      }

      final haUri = Uri.parse(widget.env.settings.resolve('/'));
      final sameOrigin = uri.origin == haUri.origin;
      final token = widget.env.settings.token;

      final headers = sameOrigin && isApiRequest && token.isNotEmpty
          ? {'Authorization': 'Bearer $token'}
          : <String, String>{};

      await _controller.loadRequest(uri, headers: headers);
    } catch (error) {
      if (!_isCurrent(generation)) return;

      setState(() {
        _error = error.toString();
        _progress = 100;
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isNativeLive) {
      final rawPtz = widget.config['ptz'];
      final ptz = rawPtz is Map
          ? rawPtz.cast<String, dynamic>()
          : const <String, dynamic>{};
      return CameraLiveView(
        key: ValueKey('camera-live-$_entity'),
        entityId: _entity!,
        env: widget.env,
        ptz: ptz,
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_hasSource) WebViewWidget(controller: _controller),
          if (_progress < 100 && _error == null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: _progress == 0 ? null : _progress / 100,
                minHeight: 2,
                backgroundColor: Colors.transparent,
              ),
            ),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.videocam_off,
                      color: Colors.white70,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loadSource,
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
