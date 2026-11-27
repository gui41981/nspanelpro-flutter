import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../util/fmt.dart';
import '../util/icons.dart';
import '../ha/connection.dart';
import 'env.dart';
import 'light_control.dart';

const _daysShort = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

/// Map Home Assistant conditions to the animated WebP assets in the
/// original icon pack. Conditions without a matching illustration keep MDI.
const _animatedWeatherAssets = <String, String>{
  'sunny': 'sunny',
  'clear': 'sunny',
  'clear-night': 'clear-night',
  'partlycloudy': 'partly-cloudy',
  'cloudy': 'cloudy',
  'fog': 'foggy',
  'hail': 'sleet',
  'lightning': 'storm',
  'lightning-rainy': 'storm',
  'rainy': 'rainy',
  'pouring': 'rainy',
  'snowy': 'snow',
  'snowy-rainy': 'sleet',
  'exceptional': 'tornado',
};

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

/// Decorative lunar overlay used only while the weather entity reports clear-night.
/// The existing Star.png background is deliberately left untouched.
// Image lunaire : NASA Goddard Space Flight Center / LROC, via Wikimedia Commons (CC BY 2.0).
class _LunarOverlay extends StatefulWidget {
  const _LunarOverlay();

  @override
  State<_LunarOverlay> createState() => _LunarOverlayState();
}

class _LunarOverlayState extends State<_LunarOverlay> {
  late final double _phase;

  @override
  void initState() {
    super.initState();
    // Calculée une seule fois à la création de l'overlay, au début de la nuit.
    _phase = _lunarPhase(DateTime.now().toUtc());
  }

  double _lunarPhase(DateTime now) {
    // Nouvelle lune connue : 2000-01-06 18:14 UTC.
    const epoch = 947182440000;
    const synodicMonth = 29.530588853 * 24 * 60 * 60 * 1000;
    final elapsed = now.millisecondsSinceEpoch - epoch;
    return ((elapsed / synodicMonth) % 1 + 1) % 1;
  }

  @override
  Widget build(BuildContext context) {
    const size = 324.0; // diamètre lunaire environ 3 fois supérieur à l'ancien.
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipOval(
              child: Image.asset(
                'assets/weather/animated/moon.jpg',
                alignment: Alignment.center,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            CustomPaint(
              painter: _MoonPhasePainter(_phase),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoonPhasePainter extends CustomPainter {
  const _MoonPhasePainter(this.phase);

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide * .5;
    final center = Offset(size.width / 2, size.height / 2);
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final angle = 2 * math.pi * phase;
    final waxing = math.sin(angle) >= 0;
    final terminatorX = math.cos(angle) * radius;

    // Silhouette de la partie non éclairée : un seul contour lunaire,
    // puis un terminateur courbe. Aucun second disque superposé.
    final shadow = Path();
    if (waxing) {
      shadow
        ..moveTo(center.dx, center.dy - radius)
        ..arcTo(bounds, -math.pi / 2, -math.pi, false)
        ..cubicTo(
          center.dx + terminatorX,
          center.dy + radius * .55,
          center.dx + terminatorX,
          center.dy - radius * .55,
          center.dx,
          center.dy - radius,
        );
    } else {
      shadow
        ..moveTo(center.dx, center.dy - radius)
        ..arcTo(bounds, -math.pi / 2, math.pi, false)
        ..cubicTo(
          center.dx - terminatorX,
          center.dy + radius * .55,
          center.dx - terminatorX,
          center.dy - radius * .55,
          center.dx,
          center.dy - radius,
        );
    }
    shadow.close();

    // Assombrissement translucide limité à la vraie zone nocturne :
    // les cratères et le relief de la photographie restent visibles.
    canvas.drawPath(
      shadow,
      Paint()
        ..shader = RadialGradient(
          center: waxing
              ? const Alignment(.55, 0)
              : const Alignment(-.55, 0),
          radius: 1.15,
          colors: const [
            Color(0xB8000000),
            Color(0x88000000),
            Color(0x66000000),
          ],
          stops: const [0, .72, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(covariant _MoonPhasePainter oldDelegate) =>
      oldDelegate.phase != phase;
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
  String? _lastNightLogKey;

  String get entity => c.str('entity') ?? '';

  List<dynamic>? _forecast;

  bool _disposed = false;
  bool _fetching = false;
  bool _refreshPending = false;
  Timer? _dailyRefresh;
  Timer? _periodicRefresh;

  final Map<String, ImageProvider> _imageProviders = <String, ImageProvider>{};

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    widget.env.conn.generationListenable.addListener(_onGenerationChanged);
    widget.env.conn.status.addListener(_onConnectionStatus);
    _onConnectionStatus();
    _armDailyRefresh();
    _periodicRefresh = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _fetchForecast(),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    widget.env.conn.generationListenable.removeListener(_onGenerationChanged);
    widget.env.conn.status.removeListener(_onConnectionStatus);
    _dailyRefresh?.cancel();
    _periodicRefresh?.cancel();
    _imageProviders.clear();
    super.dispose();
  }

  void _onGenerationChanged() {
    // Discard any response started on the previous websocket generation.
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
      _fetchForecast();
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

  /// Fetch a complete HA forecast snapshot. Forecast dates and conditions
  /// are accepted together, never from competing websocket/service streams.
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
    final conn = widget.env.conn;
    final generation = conn.generation;
    try {
      final result = await conn.send({
        'type': 'call_service',
        'domain': 'weather',
        'service': 'get_forecasts',
        'target': {'entity_id': entity},
        'service_data': {
          'type': c.str('forecast_type') ?? 'daily',
        },
        'return_response': true,
      });
      if (!mounted ||
          _disposed ||
          conn.generation != generation ||
          result is! Map) {
        return;
      }
      final response = result['response'];
      if (response is! Map) return;
      final weather = response[entity];
      if (weather is! Map) return;
      final forecast = weather['forecast'];
      if (forecast is List && forecast.isNotEmpty) {
        // Keep each date and its condition/temperatures in the same record.
        // A single service response replaces the complete displayed snapshot.
        final snapshot = forecast
            .where((entry) =>
                entry is Map &&
                DateTime.tryParse(entry['datetime']?.toString() ?? '') != null &&
                (entry['condition']?.toString().trim().isNotEmpty ?? false))
            .map((entry) => Map<String, dynamic>.from(entry as Map))
            .toList()
          ..sort((a, b) => DateTime.parse(a['datetime'].toString())
              .compareTo(DateTime.parse(b['datetime'].toString())));
        if (snapshot.isNotEmpty && mounted && !_disposed) {
          setState(() => _forecast = snapshot);
        }
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

  String _condition(HaState? s) {
    return s?.state.toLowerCase() ?? '';
  }

  String _forecastCondition(dynamic value) {
    return value?.toString().toLowerCase() ?? '';
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


  Widget _mdiWeatherIcon(String condition, double size) {
    final mdiCondition = condition == 'clear' ? 'sunny' : condition;
    return Icon(
      mdi(weatherIcons[mdiCondition] ?? 'mdi:weather-cloudy'),
      size: size,
      color: Colors.white,
      shadows: const [Shadow(blurRadius: 10, color: Colors.black87)],
    );
  }

  Widget _weatherIcon(String condition, {double size = 110}) {
    final asset = _animatedWeatherAssets[condition];
    if (asset == null) return _mdiWeatherIcon(condition, size);

    return Image.asset(
      'assets/weather/animated/$asset.webp',
      width: size,
      height: size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) {
        debugPrint('[WEATHER_ICON_ERROR] $condition: $error');
        return _mdiWeatherIcon(condition, size);
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

    // The Lovelace card controls the number of displayed days (1–8).
    // Default to five: today plus the following four days.
    // Ignore stale entries, keep today's forecast when the integration sends it,
    // and sort by date so the cards always appear in calendar order.
    final dayCount = c.intOr('forecast_count', 5).clamp(1, 8);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final afterLastDay = today.add(Duration(days: dayCount));
    final upcoming = source.where((entry) {
      if (entry is! Map) return false;
      final parsed = DateTime.tryParse(
        entry['datetime']?.toString() ?? '',
      );
      if (parsed == null) return false;
      final local = parsed.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      return !day.isBefore(today) && day.isBefore(afterLastDay);
    }).toList();

    upcoming.sort((a, b) {
      final aDate = DateTime.tryParse(a['datetime']?.toString() ?? '')!;
      final bDate = DateTime.tryParse(b['datetime']?.toString() ?? '')!;
      return aDate.compareTo(bDate);
    });
    return upcoming.take(dayCount).toList();
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

        final forecast = _forecastList(s);

        final location = _location(s);

        final configuredHeight = c.numOr('height', 0);

        final height = configuredHeight > 0
            ? configuredHeight
            : MediaQuery.sizeOf(context).height;

        return ValueListenableBuilder<HaState?>(
          valueListenable: widget.env.states.listen('sun.sun'),
          builder: (context, sun, _) {
            final night = sun?.state == 'below_horizon';
            final weatherCondition = _condition(s);
            final nightLogKey = 'sun=${sun?.state ?? 'null'}|weather=$weatherCondition|night=$night';
            if (_lastNightLogKey != nightLogKey) {
              debugPrint('[WEATHER_NIGHT_STATE] $nightLogKey');
              _lastNightLogKey = nightLogKey;
            }
            final displayCondition = night &&
                    (weatherCondition == 'sunny' || weatherCondition == 'clear')
                ? 'clear-night'
                : weatherCondition;
            final displayState = s == null
                ? null
                : HaState(
                    entityId: s.entityId,
                    state: displayCondition,
                    attributes: s.attributes,
                  );
            final condition = _conditionLabel(displayState);
            final background = _backgroundUrl(displayState);

            if (_lastBackgroundUrl != background) {
              debugPrint(
                '[WEATHER_BACKGROUND_CHANGE]'
                ' from="$_lastBackgroundUrl"'
                ' to="$background"'
                ' condition="$displayCondition"',
              );
              _lastBackgroundUrl = background;
            }

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

              if (night && !broken)
                const Positioned.fill(
                  child: Center(
                    child: _LunarOverlay(),
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
                          _weatherIcon(displayCondition, size: 110),
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
