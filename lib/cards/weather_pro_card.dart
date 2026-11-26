import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../util/fmt.dart';
import '../util/icons.dart';
import '../ha/connection.dart';
import 'env.dart';
import 'light_control.dart';

const _daysShort = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

/// HA condition names supported by the animated GIF set on the web server.
/// The existing MDI glyph remains the fallback for every missing/invalid GIF.
const _animatedWeatherConditions = <String>{
  'clear-night',
  'cloudy',
  'exceptional',
  'fog',
  'hail',
  'lightning',
  'lightning-rainy',
  'partlycloudy',
  'pouring',
  'rainy',
  'snowy',
  'snowy-rainy',
  'sunny',
  'windy',
  'windy-variant',
  // Compatibility alias used by a few weather integrations.
  'clear',
};

/// Small disk cache for animated weather GIFs. A stale file is kept and used
/// if the NAS/web server is temporarily unreachable.
class _WeatherAnimatedIconCache {
  static const _maxAge = Duration(hours: 24);
  static const _maxBytes = 5 * 1024 * 1024;
  static const _timeout = Duration(seconds: 10);

  static final Map<String, Future<File?>> _pending = {};

  static Future<File?> load(String url, String condition) {
    final key = '$condition|$url';
    return _pending.putIfAbsent(
      key,
      () => _load(url, condition).whenComplete(() => _pending.remove(key)),
    );
  }

  static Future<File?> _load(String url, String condition) async {
    File? cached;
    try {
      final support = await getApplicationSupportDirectory();
      final directory = Directory('${support.path}/weather-icons');
      await directory.create(recursive: true);

      final fileName = 'weather-$condition-${_urlHash(url)}.gif';
      final file = File('${directory.path}/$fileName');
      if (await file.exists()) {
        cached = file;
        final age = DateTime.now().difference(await file.lastModified());
        if (age < _maxAge) return file;
      }

      final client = HttpClient()
        ..connectionTimeout = _timeout;
      try {
        final request = await client.getUrl(Uri.parse(url)).timeout(_timeout);
        final response = await request.close().timeout(_timeout);
        if (response.statusCode != HttpStatus.ok ||
            response.contentLength > _maxBytes) {
          return cached;
        }

        final bytes = await response.fold<List<int>>(
          <int>[],
          (all, chunk) {
            if (all.length + chunk.length > _maxBytes) {
              throw const FormatException('Weather GIF exceeds 5 MiB');
            }
            all.addAll(chunk);
            return all;
          },
        ).timeout(_timeout);

        final signature = bytes.length >= 6
            ? String.fromCharCodes(bytes.take(6))
            : '';
        if (signature != 'GIF87a' && signature != 'GIF89a') {
          return cached;
        }

        final temporary = File('${file.path}.tmp');
        await temporary.writeAsBytes(bytes, flush: true);
        if (await file.exists()) await file.delete();
        final saved = await temporary.rename(file.path);
        await FileImage(saved).evict();
        return saved;
      } finally {
        client.close(force: true);
      }
    } catch (error) {
      debugPrint('[WEATHER_ICON_CACHE] $condition: $error');
      return cached;
    }
  }

  static String _urlHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16);
  }
}

const _daysLong = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

const _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

class _WeatherClock extends StatefulWidget {
  const _WeatherClock();

  @override
  State<_WeatherClock> createState() => _WeatherClockState();
}

class _WeatherClockState extends State<_WeatherClock> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _now = DateTime.now();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }

      final now = DateTime.now();

      // The display only has minute precision. Avoid rebuilding this
      // subtree when the displayed value did not actually change.
      if (now.minute != _now.minute ||
          now.hour != _now.hour ||
          now.day != _now.day ||
          now.month != _now.month ||
          now.year != _now.year) {
        setState(() {
          _now = now;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _timeText() {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');

    return '$h:$m';
  }

  String _dateText() {
    final weekday = _daysLong[_now.weekday - 1];
    final month = _months[_now.month - 1];

    return '$weekday ${_now.day} $month ${_now.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          _timeText(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 76,
            fontWeight: FontWeight.w700,
            height: .88,
            letterSpacing: -3,
            shadows: [Shadow(blurRadius: 8, color: Colors.black87)],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _dateText(),
          style: const TextStyle(
            color: Color(0xF2FFFFFF),
            fontSize: 20,
            fontWeight: FontWeight.w500,
            height: 1.0,
            shadows: [Shadow(blurRadius: 5, color: Colors.black87)],
          ),
        ),
      ],
    );
  }
}

class WeatherProCard extends StatefulWidget {
  const WeatherProCard({super.key, required this.config, required this.env});

  final CardConfig config;
  final PanelEnv env;

  @override
  State<WeatherProCard> createState() => _WeatherProCardState();
}

class _WeatherProCardState extends State<WeatherProCard>
    with WidgetsBindingObserver {
  CardConfig get c => widget.config;

  int _buildCount = 0;
  String? _lastBackgroundUrl;

  String get entity => c.str('entity') ?? '';

  List<dynamic>? _forecast;

  Future<void> Function()? _unsub;
  int? _subscribedGeneration;
  int? _subscribingGeneration;
  bool _disposed = false;
  bool _fetching = false;
  bool _refreshPending = false;
  Timer? _dailyRefresh;

  final Map<String, ImageProvider> _imageProviders = <String, ImageProvider>{};

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    widget.env.conn.generationListenable.addListener(_onGenerationChanged);
    widget.env.conn.status.addListener(_onConnectionStatus);
    _onConnectionStatus();
    _armDailyRefresh();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    widget.env.conn.generationListenable.removeListener(_onGenerationChanged);
    widget.env.conn.status.removeListener(_onConnectionStatus);
    _dailyRefresh?.cancel();
    _unsub?.call();
    _imageProviders.clear();
    super.dispose();
  }

  void _onGenerationChanged() {
    // Subscriptions belong to the old socket and are already gone. Do not
    // send an unsubscribe on the newly established connection.
    _unsub = null;
    _subscribedGeneration = null;
    _onConnectionStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !_disposed) {
      // Android may defer timers while asleep: recalculate the local calendar
      // and fetch the current five-day forecast immediately on resume.
      setState(() {});
      _refreshForecast();
      _armDailyRefresh();
    }
  }

  void _onConnectionStatus() {
    if (_disposed) return;
    if (widget.env.conn.status.value == HaStatus.online) {
      _maybeSubscribe();
      _fetchForecast();
    } else {
      // The old subscription is invalid after a websocket disconnect.
      _unsub = null;
    }
  }

  /// Recalculate and fetch the forecast shortly after local midnight.
  /// This runs even when the weather condition has not changed.
  void _armDailyRefresh() {
    _dailyRefresh?.cancel();
    if (!c.boolOr('show_forecast', true) || _disposed) return;

    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final delay = tomorrow.difference(now) + const Duration(seconds: 10);
    _dailyRefresh = Timer(delay, () {
      if (!mounted || _disposed) return;
      setState(() {});
      _refreshForecast();
      _armDailyRefresh();
    });
  }

  Future<void> _refreshForecast() => _fetchForecast();

  /// Explicitly request a fresh HA forecast: a subscription alone does not
  /// guarantee a new calendar payload when the weather state stays unchanged.
  Future<void> _fetchForecast() async {
    if (_disposed ||
        !c.boolOr('show_forecast', true) ||
        widget.env.conn.status.value != HaStatus.online) {
      return;
    }
    if (_fetching) {
      _refreshPending = true;
      return;
    }

    _fetching = true;
    try {
      final result = await widget.env.conn.send({
        'type': 'call_service',
        'domain': 'weather',
        'service': 'get_forecasts',
        'target': {'entity_id': entity},
        'service_data': {
          'type': c.str('forecast_type') ?? 'daily',
        },
        'return_response': true,
      });
      if (!mounted || result is! Map) return;
      final response = result['response'];
      if (response is! Map) return;
      final weather = response[entity];
      if (weather is! Map) return;
      final forecast = weather['forecast'];
      if (forecast is List) {
        setState(() => _forecast = forecast);
      }
    } catch (e) {
      // Retain the last valid forecast if HA is temporarily unavailable.
      debugPrint('weather forecast refresh failed: $e');
    } finally {
      _fetching = false;
      if (_refreshPending && !_disposed) {
        _refreshPending = false;
        scheduleMicrotask(_fetchForecast);
      }
    }
  }

  Future<void> _maybeSubscribe() async {
    if (!c.boolOr('show_forecast', true)) {
      return;
    }

    final conn = widget.env.conn;
    final generation = conn.generation;

    // Wait until _seed has completed, not merely until auth_ok arrives.
    if (conn.status.value != HaStatus.online || generation == 0) {
      return;
    }

    if (_subscribedGeneration == generation ||
        _subscribingGeneration == generation) {
      return;
    }

    _subscribingGeneration = generation;

    try {
      final unsubscribe = await conn.subscribe(
        {
          'type': 'weather/subscribe_forecast',
          'forecast_type': c.str('forecast_type') ?? 'daily',
          'entity_id': entity,
        },
        (ev) {
          if (!mounted || conn.generation != generation) {
            return;
          }

          final forecast = (ev as Map?)?['forecast'] as List? ?? const [];

          setState(() {
            _forecast = forecast;
          });
        },
      );

      // The socket may have changed while the subscription was pending.
      if (!mounted ||
          conn.generation != generation ||
          conn.status.value != HaStatus.online) {
        await unsubscribe();
        return;
      }

      _unsub = unsubscribe;
      _subscribedGeneration = generation;
    } catch (_) {
      // Forecast subscription is optional.
    } finally {
      if (_subscribingGeneration == generation) {
        _subscribingGeneration = null;
      }
    }
  }

  String _condition(HaState? s) {
    return s?.state.toLowerCase() ?? '';
  }

  String _forecastCondition(dynamic value) {
    return value?.toString().toLowerCase() ?? '';
  }

  bool _night(HaState? s) {
    return _condition(s) == 'clear-night';
  }

  String _background(HaState? s) {
    switch (_condition(s)) {
      case 'clear-night':
        return 'Star.png';

      case 'sunny':
      case 'clear':
        return 'Sunny.png';

      case 'partlycloudy':
      case 'cloudy':
      case 'fog':
      case 'windy':
      case 'windy-variant':
        return 'Cloud.png';

      case 'rainy':
      case 'pouring':
      case 'hail':
        return 'Rain.png';

      case 'snowy':
      case 'snowy-rainy':
        return 'Snow.png';

      case 'lightning':
      case 'lightning-rainy':
        return 'Thunder.png';

      default:
        return 'Cloud.png';
    }
  }

  String _weatherImage(String condition) {
    switch (condition) {
      case 'clear-night':
        return 'Star.png';

      case 'sunny':
      case 'clear':
        return 'Sunny.png';

      case 'partlycloudy':
      case 'cloudy':
      case 'fog':
      case 'windy':
      case 'windy-variant':
        return 'Cloud.png';

      case 'rainy':
      case 'pouring':
      case 'hail':
        return 'Rain.png';

      case 'snowy':
      case 'snowy-rainy':
        return 'Snow.png';

      case 'lightning':
      case 'lightning-rainy':
        return 'Thunder.png';

      default:
        return 'Cloud.png';
    }
  }

  String _backgroundUrl(HaState? s) {
    final base = c.str('background_url') ?? '/local/nspanel-weather';

    final file = _background(s);

    final url = base.endsWith('/') ? '$base$file' : '$base/$file';

    return widget.env.settings.resolve(url);
  }

  String? _animatedWeatherIconUrl(String condition) {
    if (!_animatedWeatherConditions.contains(condition)) return null;

    final base =
        c.str('animated_icon_url') ?? '/local/nspanel-weather/animated';
    final file = '$condition.gif';
    final url = base.endsWith('/') ? '$base$file' : '$base/$file';
    return widget.env.settings.resolve(url);
  }

  Widget _mdiWeatherIcon(String condition, double size) {
    return Icon(
      mdi(weatherIcons[condition] ?? 'mdi:weather-cloudy'),
      size: size,
      color: Colors.white,
      shadows: const [Shadow(blurRadius: 10, color: Colors.black87)],
    );
  }

  Widget _weatherIcon(String condition, {double size = 110}) {
    final url = _animatedWeatherIconUrl(condition);
    if (url == null) return _mdiWeatherIcon(condition, size);

    return FutureBuilder<File?>(
      future: _WeatherAnimatedIconCache.load(url, condition),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) return _mdiWeatherIcon(condition, size);

        return Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (context, error, stack) {
            debugPrint(
              '[WEATHER_ICON_ERROR] condition="$condition"'
              ' file="${file.path}" error=$error',
            );
            return _mdiWeatherIcon(condition, size);
          },
        );
      },
    );
  }

  String _forecastImageUrl(String condition) {
    final base =
        c.str('forecast_image_url') ?? '/local/nspanel-weather/forecast';

    final file = _weatherImage(condition);

    final url = base.endsWith('/') ? '$base$file' : '$base/$file';

    return widget.env.settings.resolve(url);
  }

  ImageProvider _imageProvider(
    String url,
    BuildContext context, {
    int? width,
    int? height,
  }) {
    final mediaSize =
        MediaQuery.sizeOf(context) * MediaQuery.devicePixelRatioOf(context);

    final targetWidth = width ?? mediaSize.width.round();
    final targetHeight = height ?? mediaSize.height.round();

    final key = '$url|${targetWidth}x$targetHeight';

    final cached = _imageProviders[key];
    if (cached != null) {
      return cached;
    }

    debugPrint(
      '[WEATHER_IMAGE] provider'
      ' url="$url"'
      ' target=${targetWidth}x$targetHeight'
      ' logical=${MediaQuery.sizeOf(context)}'
      ' dpr=${MediaQuery.devicePixelRatioOf(context)}',
    );

    final provider = ResizeImage(
      NetworkImage(url),
      width: targetWidth,
      height: targetHeight,
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    );

    _imageProviders[key] = provider;

    return provider;
  }

  String _conditionLabel(HaState? s) {
    switch (_condition(s)) {
      case 'sunny':
        return 'Ensoleillé';
      case 'clear':
        return 'Dégagé';
      case 'clear-night':
        return 'Ciel dégagé';
      case 'partlycloudy':
        return 'Partiellement nuageux';
      case 'cloudy':
        return 'Nuageux';
      case 'rainy':
        return 'Pluie';
      case 'pouring':
        return 'Forte pluie';
      case 'snowy':
        return 'Neige';
      case 'snowy-rainy':
        return 'Neige et pluie';
      case 'lightning':
        return 'Orage';
      case 'lightning-rainy':
        return 'Orage et pluie';
      case 'hail':
        return 'Grêle';
      case 'fog':
        return 'Brouillard';
      case 'windy':
      case 'windy-variant':
        return 'Venteux';
      default:
        final value = _condition(s).replaceAll('-', ' ');

        return value.isEmpty ? '' : value[0].toUpperCase() + value.substring(1);
    }
  }

  List<dynamic> _forecastList(HaState? s) {
    if (!c.boolOr('show_forecast', true)) {
      return const [];
    }

    final source =
        _forecast ?? (s?.attributes['forecast'] as List?) ?? const [];

    // The page shows the next five calendar days, starting tomorrow. Drop
    // today's entry and any stale dates left at the front by the integration.
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final afterFifthDay = tomorrow.add(const Duration(days: 5));
    final upcoming = source.where((entry) {
      if (entry is! Map) return false;
      final parsed = DateTime.tryParse(
        entry['datetime']?.toString() ?? '',
      );
      if (parsed == null) return false;
      final local = parsed.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      return !day.isBefore(tomorrow) && day.isBefore(afterFifthDay);
    }).toList();

    upcoming.sort((a, b) {
      final aDate = DateTime.tryParse(a['datetime']?.toString() ?? '')!;
      final bDate = DateTime.tryParse(b['datetime']?.toString() ?? '')!;
      return aDate.compareTo(bDate);
    });
    return upcoming.take(5).toList();
  }

  String _location(HaState? s) {
    final configured = c.str('location');

    if (configured != null && configured.trim().isNotEmpty) {
      return configured.trim();
    }

    final rawEntity = entity.contains('.') ? entity.split('.').last : entity;

    if (rawEntity.trim().isNotEmpty) {
      final words = rawEntity.replaceAll('_', ' ').trim().split(RegExp(r'\s+'));

      final formatted = words
          .where((word) => word.isNotEmpty)
          .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
          .join(' ');

      if (formatted.isNotEmpty) {
        return formatted;
      }
    }

    return friendlyName(s, entity);
  }

  String _forecastDate(dynamic forecast) {
    final map = forecast is Map ? forecast : const {};

    final value = map['datetime']?.toString();

    if (value == null || value.isEmpty) {
      return '';
    }

    final date = DateTime.tryParse(value)?.toLocal();

    if (date == null) {
      return '';
    }

    return '${_daysShort[date.weekday - 1]} ${date.day}';
  }

  num? _num(dynamic value) {
    if (value is num) {
      return value;
    }

    if (value == null) {
      return null;
    }

    return num.tryParse(value.toString());
  }


  List<String> _lightEntities(CardConfig light) {
    final configured = light['entities'];

    if (configured is List) {
      final values = configured
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList();

      if (values.isNotEmpty) {
        return values;
      }
    }

    final entity = light.str('entity')?.trim();
    return entity == null || entity.isEmpty ? const [] : [entity];
  }

  List<CardConfig> get _embeddedLights => c
      .maps('_embedded_lights')
      .where((light) => _lightEntities(light).isNotEmpty)
      .toList();

  String _lightIcon(CardConfig light) {
    final configured = light.str('icon');
    if (configured != null && configured.trim().isNotEmpty) {
      return configured;
    }

    // Les icônes sont choisies à partir du titre YAML, jamais de l'entité.
    final title = (light.str('title') ?? light.str('name') ?? '')
        .toLowerCase();

    if (title.contains('salon')) return 'mdi:sofa';
    if (title.contains('tv')) return 'mdi:television';
    if (title.contains('veilleuse')) return 'mdi:floor-lamp';
    if (title.contains('cuisine')) return 'mdi:silverware-fork-knife';

    return 'mdi:lightbulb-on-outline';
  }

  Widget _lightButton(CardConfig light) {
    final entities = _lightEntities(light);
    final fallback = entities.isEmpty ? 'Light' : entities.first;
    final title = light.titleOr(fallback);

    return LightControl(
      label: title,
      icon: _lightIcon(light),
      entities: entities,
      env: widget.env,
    );
  }

  Widget _switchesBlock() {
    final lights = _embeddedLights;

    if (lights.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final isLargePanel = screenWidth >= 600;
        final width = isLargePanel
            ? (screenWidth - 80).clamp(520.0, 680.0)
            : 430.0;
        final rowCount = (lights.length + 1) ~/ 2;

        return SizedBox(
          width: width,
          child: Column(
            children: [
              for (var row = 0; row < rowCount; row++) ...[
                if (row > 0) SizedBox(height: isLargePanel ? 16 : 7),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _lightButton(lights[row * 2]),
                      ),
                      SizedBox(width: isLargePanel ? 10 : 8),
                      Expanded(
                        child: row * 2 + 1 < lights.length
                            ? _lightButton(lights[row * 2 + 1])
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _buildCount++;

    debugPrint('[WEATHER_BUILD] count=$_buildCount entity=$entity');

    return ValueListenableBuilder<HaState?>(
      valueListenable: widget.env.states.listen(entity),
      builder: (context, s, _) {
        final broken = s == null || s.isBroken;

        final temperature = s?.numAttr('temperature');

        final unit = s?.attr<String>('temperature_unit') ?? '°';

        final humidity = s?.numAttr('humidity');

        final wind = s?.numAttr('wind_speed');

        final windUnit = s?.attr<String>('wind_speed_unit') ?? '';

        final condition = _conditionLabel(s);

        final night = _night(s);

        final forecast = _forecastList(s);

        final background = _backgroundUrl(s);

        if (_lastBackgroundUrl != background) {
          debugPrint(
            '[WEATHER_BACKGROUND_CHANGE]'
            ' from="$_lastBackgroundUrl"'
            ' to="$background"'
            ' condition="${_condition(s)}"',
          );
          _lastBackgroundUrl = background;
        }

        final location = _location(s);

        final configuredHeight = c.numOr('height', 0);

        final height = configuredHeight > 0
            ? configuredHeight
            : MediaQuery.sizeOf(context).height;

        return Container(
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(c.numOr('radius', 0)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image(
                image: _imageProvider(background, context),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stack) {
                  debugPrint(
                    '[WEATHER_IMAGE_ERROR] background'
                    ' url="$background"'
                    ' error=$error',
                  );

                  debugPrint('[WEATHER_IMAGE_ERROR] background stack=$stack');

                  return const ColoredBox(color: Colors.black);
                },
              ),

              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.20, 0.65, 1.0],
                    colors: [
                      Color(0x88000000),
                      Color(0x22000000),
                      Color(0x22000000),
                      Color(0x99000000),
                    ],
                  ),
                ),
              ),

              if (broken)
                const Positioned.fill(
                  child: ColoredBox(color: Color(0x66000000)),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w600,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 6,
                                      color: Colors.black87,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (!broken)
                                Text(
                                  condition,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xE6FFFFFF),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    shadows: [
                                      Shadow(
                                        blurRadius: 4,
                                        color: Colors.black87,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [const _WeatherClock()],
                        ),
                      ],
                    ),

                    if (c.boolOr('show_switches', false) &&
                        !broken &&
                        _embeddedLights.isNotEmpty)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 14, bottom: 14),
                          child: _switchesBlock(),
                        ),
                      )
                    else
                      const Spacer(),

                    if (!broken)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      temperature == null
                                          ? '—'
                                          : fmt(temperature, 0),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 76,
                                        height: .88,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -3,
                                        shadows: [
                                          Shadow(
                                            blurRadius: 8,
                                            color: Colors.black87,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (temperature != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 5,
                                          top: 3,
                                        ),
                                        child: Text(
                                          unit,
                                          style: const TextStyle(
                                            color: Color(0xEEFFFFFF),
                                            fontSize: 29,
                                            fontWeight: FontWeight.w600,
                                            shadows: [
                                              Shadow(
                                                blurRadius: 5,
                                                color: Colors.black87,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 7),
                                Row(
                                  children: [
                                    if (humidity != null)
                                      _info(
                                        Icons.water_drop_outlined,
                                        '${fmt(humidity, 0)} %',
                                      ),
                                    if (humidity != null && wind != null)
                                      const SizedBox(width: 18),
                                    if (wind != null)
                                      _info(
                                        Icons.air,
                                        '${fmt(wind, 0)} $windUnit'.trim(),
                                      ),
                                    if (night) ...[
                                      const SizedBox(width: 18),
                                      _info(Icons.nightlight_round, 'Nuit'),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          _weatherIcon(_condition(s), size: 110),
                        ],
                      ),

                    const SizedBox(height: 14),

                    if (forecast.isNotEmpty)
                      SizedBox(
                        height: 116,
                        child: Row(
                          children: [
                            for (var i = 0; i < forecast.length; i++) ...[
                              if (i > 0) const SizedBox(width: 7),
                              Expanded(
                                child: _forecastDay(forecast[i], unit, context),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              if (broken)
                const Positioned(
                  right: 18,
                  top: 18,
                  child: Text(
                    'HORS LIGNE',
                    style: TextStyle(
                      color: Color(0xFFFF7777),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _info(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 18,
          color: Colors.white,
          shadows: const [Shadow(blurRadius: 4, color: Colors.black87)],
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(blurRadius: 4, color: Colors.black87)],
          ),
        ),
      ],
    );
  }

  Widget _forecastDay(dynamic forecast, String unit, BuildContext context) {
    final map = forecast is Map ? forecast : const {};

    final condition = _forecastCondition(map['condition']);

    final high = _num(map['temperature']);

    final low = _num(map['templow']);

    final date = _forecastDate(forecast);

    final imageUrl = _forecastImageUrl(condition);

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 5, 4, 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .20)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            date,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xF2FFFFFF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(blurRadius: 3, color: Colors.black87)],
            ),
          ),
          const SizedBox(height: 1),
          Expanded(
            child: Image(
              image: _imageProvider(imageUrl, context, width: 70, height: 55),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) {
                debugPrint(
                  '[WEATHER_IMAGE_ERROR] forecast'
                  ' url="$imageUrl"'
                  ' error=$error',
                );

                debugPrint('[WEATHER_IMAGE_ERROR] forecast stack=$stack');

                return const SizedBox.shrink();
              },
            ),
          ),
          const SizedBox(height: 1),
          Text.rich(
            TextSpan(
              children: [
                if (high != null)
                  TextSpan(
                    text: fmt(high, 0),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (high != null && low != null)
                  const TextSpan(
                    text: ' / ',
                    style: TextStyle(color: Color(0x99FFFFFF), fontSize: 12),
                  ),
                if (low != null)
                  TextSpan(
                    text: fmt(low, 0),
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
