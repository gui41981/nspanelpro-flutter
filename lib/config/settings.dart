import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where Home Assistant is and how to prove who we are. Stored on the panel
/// and nowhere else.
class Settings {
  Settings({
    required this.url,
    required this.token,
    this.dashboard = '',
    this.cachedConfig,
    this.screensaver,
    this.mqtt,
    this.name = 'NSPanel',
    this.ttsEngine = '',
    this.feedback,
    this.overrides,
    this.brightness,
  });

  String url;
  String token;

  Map<String, dynamic>? screensaver;
  Map<String, dynamic>? mqtt;
  String name;
  String ttsEngine;
  Map<String, dynamic>? feedback;
  Map<String, dynamic>? overrides;
  Map<String, dynamic>? brightness;

  bool get autoBrightness =>
      brightness?['auto'] is bool ? brightness!['auto'] as bool : false;

  int get brightnessMin =>
      ((brightness?['min'] as num?)?.toInt() ?? 20).clamp(0, 255);

  int get brightnessMax =>
      ((brightness?['max'] as num?)?.toInt() ?? 255).clamp(0, 255);

  double get brightnessDaylight =>
      ((brightness?['daylight_lux'] as num?)?.toDouble() ?? 500).clamp(
        10,
        100000,
      );

  bool get touchSound =>
      feedback?['sound'] is bool ? feedback!['sound'] as bool : true;

  bool get touchVibrate =>
      feedback?['vibrate'] is bool ? feedback!['vibrate'] as bool : true;

  double get touchVolume =>
      ((feedback?['volume'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);

  String get mqttHost => mqtt?['host']?.toString().trim() ?? '';

  int get mqttPort => (mqtt?['port'] as num?)?.toInt() ?? 1883;

  String? get mqttUser =>
      (mqtt?['username']?.toString().trim().isEmpty ?? true)
          ? null
          : mqtt!['username'].toString().trim();

  String? get mqttPass =>
      (mqtt?['password']?.toString().isEmpty ?? true)
          ? null
          : mqtt!['password'].toString();

  bool get hasMqtt => mqttHost.isNotEmpty;

  String dashboard;

  String? cachedConfig;

  static const _kUrl = 'url';
  static const _kToken = 'token';
  static const _kDash = 'dashboard';
  static const _kCache = 'cached_config';
  static const _kSaver = 'screensaver';
  static const _kMqtt = 'mqtt';
  static const _kName = 'name';
  static const _kTts = 'tts_engine';
  static const _kFeedback = 'feedback';
  static const _kOverrides = 'overrides';
  static const _kBrightness = 'brightness';

  static Map<String, dynamic>? _map(SharedPreferences p, String key) {
    final raw = p.getString(key);
    if (raw == null) return null;

    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> consumeSetupFile() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return false;

      final f = File(
        '${dir.path}${Platform.pathSeparator}setup.json',
      );

      if (!await f.exists()) return false;

      final j = jsonDecode(await f.readAsString());
      await f.delete();

      if (j is! Map) return false;

      final current = await load();

      final url =
          j['url']?.toString().trim() ?? current?.url ?? '';

      final token =
          j['token']?.toString().trim() ?? current?.token ?? '';

      if (url.isEmpty || token.isEmpty) return false;

      final s = Settings(
        url: url,
        token: token,
        dashboard: j.containsKey('dashboard')
            ? (j['dashboard']?.toString().trim() ?? '')
            : (current?.dashboard ?? ''),
        cachedConfig: current?.cachedConfig,
        screensaver: j.containsKey('screensaver')
            ? (j['screensaver'] is Map
                  ? (j['screensaver'] as Map).cast<String, dynamic>()
                  : null)
            : current?.screensaver,
        mqtt: j.containsKey('mqtt')
            ? (j['mqtt'] is Map
                  ? (j['mqtt'] as Map).cast<String, dynamic>()
                  : null)
            : current?.mqtt,
        name: j['name']?.toString().trim() ??
            current?.name ??
            'NSPanel',
        ttsEngine:
            j['tts_engine']?.toString().trim() ??
            current?.ttsEngine ??
            '',
        feedback: j.containsKey('feedback')
            ? (j['feedback'] is Map
                  ? (j['feedback'] as Map).cast<String, dynamic>()
                  : null)
            : current?.feedback,
        overrides: current?.overrides,
        brightness: j.containsKey('brightness')
            ? (j['brightness'] is Map
                  ? (j['brightness'] as Map).cast<String, dynamic>()
                  : null)
            : current?.brightness,
      );

      await s.save();
      return true;
    } catch (e) {
      debugPrint('setup.json: $e');
      return false;
    }
  }

  static Future<Settings?> load() async {
    final p = await SharedPreferences.getInstance();

    final url = p.getString(_kUrl);
    final token = p.getString(_kToken);

    if (url == null ||
        url.isEmpty ||
        token == null ||
        token.isEmpty) {
      return null;
    }

    return Settings(
      url: url,
      token: token,
      dashboard: p.getString(_kDash) ?? '',
      cachedConfig: p.getString(_kCache),
      screensaver: _map(p, _kSaver),
      mqtt: _map(p, _kMqtt),
      name: p.getString(_kName) ?? 'NSPanel',
      ttsEngine: p.getString(_kTts) ?? '',
      feedback: _map(p, _kFeedback),
      overrides: _map(p, _kOverrides),
      brightness: _map(p, _kBrightness),
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();

    await p.setString(_kUrl, url);
    await p.setString(_kToken, token);
    await p.setString(_kDash, dashboard);
    await p.setString(_kName, name);
    await p.setString(_kTts, ttsEngine);

    final maps = {
      _kSaver: screensaver,
      _kMqtt: mqtt,
      _kFeedback: feedback,
      _kOverrides: overrides,
      _kBrightness: brightness,
    };

    for (final e in maps.entries) {
      if (e.value == null) {
        await p.remove(e.key);
      } else {
        await p.setString(e.key, jsonEncode(e.value));
      }
    }
  }

  Future<void> cacheConfig(String json) async {
    cachedConfig = json;

    final p = await SharedPreferences.getInstance();

    await p.setString(_kCache, json);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();

    await p.remove(_kUrl);
    await p.remove(_kToken);
    await p.remove(_kDash);
    await p.remove(_kCache);
    await p.remove(_kSaver);
    await p.remove(_kMqtt);
    await p.remove(_kName);
    await p.remove(_kTts);
    await p.remove(_kOverrides);
    await p.remove(_kBrightness);
  }

  String get dashboardPath => normaliseDashboard(dashboard);

  static String normaliseDashboard(String raw) {
    var s = raw.trim();

    if (s.contains('://')) {
      s = Uri.tryParse(s)?.path ?? s;
    }

    s = s.replaceAll(RegExp(r'^/+'), '');

    final parts =
        s.split('/').where((p) => p.isNotEmpty).toList();

    if (parts.isEmpty) return '';

    if (parts.first == 'lovelace') return '';

    return parts.first;
  }

  Uri get base {
    var raw = url.trim();

    if (!raw.contains('://')) {
      raw = 'http://$raw';
    }

    return Uri.parse(raw);
  }

  Uri get wsUri {
    final b = base;

    return b.replace(
      scheme: b.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/websocket',
    );
  }

  String resolve(String path) {
    if (!path.startsWith('/')) return path;

    final b = base;

    return '${b.scheme}://${b.authority}$path';
  }
}
