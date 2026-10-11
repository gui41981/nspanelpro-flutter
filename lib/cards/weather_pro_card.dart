import 'dart:async';

import 'package:flutter/material.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../util/fmt.dart';
import '../util/icons.dart';
import '../ha/connection.dart';
import 'env.dart';
import 'light_control.dart';

const _daysShort = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

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

class _WeatherProCardState extends State<WeatherProCard> {
  CardConfig get c => widget.config;

  int _buildCount = 0;
  String? _lastBackgroundUrl;

  String get entity => c.str('entity') ?? '';

  List<dynamic>? _forecast;

  Future<void> Function()? _unsub;
  bool _subscribing = false;

  final Map<String, ImageProvider> _imageProviders = <String, ImageProvider>{};

  @override
  void initState() {
    super.initState();

    widget.env.conn.status.addListener(_maybeSubscribe);
    _maybeSubscribe();
  }

  @override
  void dispose() {
    widget.env.conn.status.removeListener(_maybeSubscribe);
    _unsub?.call();
    _imageProviders.clear();
    super.dispose();
  }

  Future<void> _maybeSubscribe() async {
    if (!c.boolOr('show_forecast', true)) {
      return;
    }

    if (_unsub != null || _subscribing) {
      return;
    }

    if (widget.env.conn.status.value != HaStatus.online) {
      return;
    }

    _subscribing = true;

    try {
      _unsub = await widget.env.conn.subscribe(
        {
          'type': 'weather/subscribe_forecast',
          'forecast_type': c.str('forecast_type') ?? 'daily',
          'entity_id': entity,
        },
        (ev) {
          if (!mounted) {
            return;
          }

          final forecast = (ev as Map?)?['forecast'] as List? ?? const [];

          setState(() {
            _forecast = forecast;
          });
        },
      );
    } catch (_) {
      // Forecast subscription is optional.
    } finally {
      _subscribing = false;
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

    return source.take(5).toList();
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
                          Icon(
                            mdi(
                              weatherIcons[_condition(s)] ??
                                  'mdi:weather-cloudy',
                            ),
                            size: 110,
                            color: Colors.white,
                            shadows: const [
                              Shadow(blurRadius: 10, color: Colors.black87),
                            ],
                          ),
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
