import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/settings.dart';
import '../ha/panels.dart';
import '../ui/theme.dart';

/// Displays one Home Assistant built-in panel.
///
/// A new controller is created when this widget is mounted.
/// Flutter disposes of the platform view when the widget is removed.
class BuiltInPanelView extends StatefulWidget {
  const BuiltInPanelView({
    super.key,
    required this.panel,
    required this.settings,
  });

  final HaPanel panel;
  final Settings settings;

  @override
  State<BuiltInPanelView> createState() => _BuiltInPanelViewState();
}

class _BuiltInPanelViewState extends State<BuiltInPanelView> {
  WebViewController? _controller;
  int _progress = 0;
  String? _error;
  bool _disposed = false;
  int _generation = 0;

  String get _url {
    var path = widget.panel.urlPath.trim();

    if (path.isEmpty) {
      path = widget.panel.id;
    }

    path = path.replaceFirst(RegExp(r'^/+'), '');
    return widget.settings.resolve('/$path');
  }

  @override
  void initState() {
    super.initState();
    _createWebView();
  }

  bool _isCurrent(int generation) =>
      mounted && !_disposed && generation == _generation;

  Future<void> _createWebView() async {
    final generation = ++_generation;
    final controller = WebViewController();

    _controller = controller;
    setState(() {
      _progress = 0;
      _error = null;
    });

    await _configureAndLoad(controller, generation);
  }

  Future<void> _configureAndLoad(
    WebViewController controller,
    int generation,
  ) async {
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (!_isCurrent(generation)) return;

      await controller.setBackgroundColor(const Color(0xFF111318));
      if (!_isCurrent(generation)) return;

      await controller.setNavigationDelegate(
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

      await controller.loadRequest(Uri.parse(_url));
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
    _disposed = true;
    _generation++;
    _controller = null;
    super.dispose();
  }

  Future<void> _retry() async {
    if (!mounted || _disposed) return;

    final controller = _controller;
    if (controller == null) {
      return;
    }

    final generation = ++_generation;
    setState(() {
      _progress = 0;
      _error = null;
    });

    await _configureAndLoad(controller, generation);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (controller == null) {
      return const ColoredBox(
        color: Color(0xFF111318),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: controller),
        if (_progress < 100 && _error == null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: _progress == 0 ? null : _progress / 100,
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: Ns.gold,
            ),
          ),
        if (_error != null)
          ColoredBox(
            color: const Color(0xFF111318),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off,
                      color: Colors.redAccent,
                      size: 30,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Home Assistant inaccessible',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _retry,
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
