import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';

import '../config/dashboard.dart';
import '../ha/connection.dart';
import '../ha/states.dart';
import '../util/fmt.dart';
import '../util/icons.dart';
import 'env.dart';

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

class WeatherProCard extends StatefulWidget {
  const WeatherProCard({super.key, required this.config, required this.env});

  final CardConfig config;
  final PanelEnv env;

  @override
  State<WeatherProCard> createState() => _WeatherProCardState();
}

class _WeatherProCardState extends State<WeatherProCard> {
  CardConfig get c => widget.config;

  String get entity => c.str('entity') ?? '';

  List<dynamic>? _forecast;

  Future<void> Function()? _unsub;
  bool _subscribing = false;

  late DateTime _now;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();

    _now = DateTime.now();

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });

    widget.env.conn.status.addListener(_maybeSubscribe);
    _maybeSubscribe();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    widget.env.conn.status.removeListener(_maybeSubscribe);
    _unsub?.call();
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

    debugPrint(
      '[WEATHER_IMAGE] provider'
      ' url="$url"'
      ' target=${targetWidth}x$targetHeight'
      ' logical=${MediaQuery.sizeOf(context)}'
      ' dpr=${MediaQuery.devicePixelRatioOf(context)}',
    );

    return ResizeImage(
      NetworkImage(url),
      width: targetWidth,
      height: targetHeight,
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    );
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

  Future<void> _setLights(List<String> entities, bool on) async {
    if (entities.isEmpty) {
      return;
    }

    try {
      await widget.env.conn.callService(
        'homeassistant',
        on ? 'turn_on' : 'turn_off',
        {'entity_id': entities},
      );
    } catch (e) {
      debugPrint('weather_pro_card light service failed: $e');
    }
  }

  Widget _lightButton({
    required String label,
    required String icon,
    required List<String> entities,
  }) {
    return ValueListenableBuilder<HaState?>(
      valueListenable: widget.env.states.listen(entities.first),
      builder: (context, firstState, _) {
        return _LightButtonContent(
          label: label,
          icon: icon,
          entities: entities,
          firstState: firstState,
          states: widget.env.states,
          conn: widget.env.conn,
          onSet: _setLights,
        );
      },
    );
  }

  Widget _switchesBlock() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.sizeOf(context).width;

        final isLargePanel = screenWidth >= 600;

        final width = isLargePanel
            ? (screenWidth - 80).clamp(520.0, 680.0)
            : 430.0;

        return SizedBox(
          width: width,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: _lightButton(
                        label: 'Salon',
                        icon: 'mdi:sofa',
                        entities: const [
                          'light.wiz_tunable_white_992e58',
                          'light.wiz_st64_filament_2',
                        ],
                      ),
                    ),
                    SizedBox(height: isLargePanel ? 16 : 7),
                    Expanded(
                      child: _lightButton(
                        label: 'Veilleuse',
                        icon: 'mdi:floor-lamp',
                        entities: const ['light.wiz_rgbw_tunable_120924'],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: isLargePanel ? 10 : 8),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: _lightButton(
                        label: 'TV',
                        icon: 'mdi:television',
                        entities: const ['light.wiz_rgbw_tunable_32ccbc'],
                      ),
                    ),
                    SizedBox(height: isLargePanel ? 16 : 7),
                    Expanded(
                      child: _lightButton(
                        label: 'Cuisine',
                        icon: 'mdi:silverware-fork-knife',
                        entities: const [
                          'light.wiz_tunable_white_2fe460',
                          'light.wiz_tunable_white_842be2',
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
                          children: [
                            Text(
                              _timeText(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 76,
                                fontWeight: FontWeight.w700,
                                height: .88,
                                letterSpacing: -3,
                                shadows: [
                                  Shadow(blurRadius: 8, color: Colors.black87),
                                ],
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
                                shadows: [
                                  Shadow(blurRadius: 5, color: Colors.black87),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    if (c.boolOr('show_switches', false) && !broken)
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

class _LightButtonContent extends StatelessWidget {
  const _LightButtonContent({
    required this.label,
    required this.icon,
    required this.entities,
    required this.firstState,
    required this.states,
    required this.conn,
    required this.onSet,
  });

  final String label;
  final String icon;
  final List<String> entities;
  final HaState? firstState;
  final dynamic states;
  final dynamic conn;
  final Future<void> Function(List<String> entities, bool on) onSet;

  @override
  Widget build(BuildContext context) {
    return _MultiLightButton(
      label: label,
      icon: icon,
      entities: entities,
      firstState: firstState,
      states: states,
      conn: conn,
      onSet: onSet,
    );
  }
}

class _MultiLightButton extends StatefulWidget {
  const _MultiLightButton({
    required this.label,
    required this.icon,
    required this.entities,
    required this.firstState,
    required this.states,
    required this.conn,
    required this.onSet,
  });

  final String label;
  final String icon;
  final List<String> entities;
  final HaState? firstState;
  final dynamic states;
  final dynamic conn;
  final Future<void> Function(List<String> entities, bool on) onSet;

  @override
  State<_MultiLightButton> createState() => _MultiLightButtonState();
}

class _MultiLightButtonState extends State<_MultiLightButton> {

  @override
  Widget build(BuildContext context) {
    final List<Listenable> listenables = [
      for (final entity in widget.entities)
        widget.states.listen(entity) as Listenable,
    ];

    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        final on = widget.entities.any(
          (entity) => widget.states.get(entity)?.isOn == true,
        );

        return _button(on);
      },
    );
  }

  List<HaState> _states() {
    return [
      for (final entity in widget.entities)
        if (widget.states.get(entity) is HaState)
          widget.states.get(entity) as HaState,
    ];
  }

  List<String> _effectList() {
    final result = <String>{};

    for (final state in _states()) {
      final effects = state.attributes['effect_list'];

      if (effects is List) {
        for (final effect in effects) {
          final value = effect?.toString().trim();

          if (value != null && value.isNotEmpty) {
            result.add(value);
          }
        }
      }
    }

    return result.toList()..sort();
  }

  Set<String> _colorModes() {
    final result = <String>{};

    for (final state in _states()) {
      final modes = state.attributes['supported_color_modes'];

      if (modes is List) {
        for (final mode in modes) {
          final value = mode?.toString().trim();

          if (value != null && value.isNotEmpty) {
            result.add(value);
          }
        }
      }
    }

    return result;
  }

  bool _supportsColor() {
    final modes = _colorModes();

    return modes.contains('rgb') ||
        modes.contains('rgbw') ||
        modes.contains('rgbww') ||
        modes.contains('hs') ||
        modes.contains('xy');
  }

  bool _supportsTemperature() {
    final modes = _colorModes();

    return modes.contains('color_temp') ||
        modes.contains('rgbww') ||
        modes.contains('rgbw');
  }

  List<String> _entitiesWithCapability(bool Function(Set<String>) test) {
    final result = <String>[];

    for (final entity in widget.entities) {
      final state = widget.states.get(entity);

      if (state is! HaState) {
        continue;
      }

      final modes = state.attributes['supported_color_modes'];

      final normalized = <String>{};

      if (modes is List) {
        for (final mode in modes) {
          normalized.add(mode.toString());
        }
      }

      if (test(normalized)) {
        result.add(entity);
      }
    }

    return result;
  }

  int _brightness() {
    for (final state in _states()) {
      final value = state.attributes['brightness'];

      if (value is num) {
        return value.round().clamp(1, 255);
      }
    }

    return 255;
  }

  int _red() {
    for (final state in _states()) {
      final rgb = state.attributes['rgb_color'];

      if (rgb is List && rgb.length >= 3) {
        return (rgb[0] as num).round().clamp(0, 255);
      }
    }

    return 255;
  }

  int _green() {
    for (final state in _states()) {
      final rgb = state.attributes['rgb_color'];

      if (rgb is List && rgb.length >= 3) {
        return (rgb[1] as num).round().clamp(0, 255);
      }
    }

    return 255;
  }

  int _blue() {
    for (final state in _states()) {
      final rgb = state.attributes['rgb_color'];

      if (rgb is List && rgb.length >= 3) {
        return (rgb[2] as num).round().clamp(0, 255);
      }
    }

    return 255;
  }

  int _colorTemperature() {
    for (final state in _states()) {
      final kelvin = state.attributes['color_temp_kelvin'];

      if (kelvin is num) {
        return kelvin.round();
      }

      final mired = state.attributes['color_temp'];

      if (mired is num && mired > 0) {
        return (1000000 / mired).round();
      }
    }

    return 4000;
  }

  int _minColorTemperature() {
    int? result;

    for (final state in _states()) {
      final value = state.attributes['min_color_temp_kelvin'];

      if (value is num) {
        final current = value.round();

        if (result == null || current > result) {
          result = current;
        }
      }
    }

    return result ?? 2000;
  }

  int _maxColorTemperature() {
    int? result;

    for (final state in _states()) {
      final value = state.attributes['max_color_temp_kelvin'];

      if (value is num) {
        final current = value.round();

        if (result == null || current < result) {
          result = current;
        }
      }
    }

    return result ?? 6500;
  }

  Future<void> _callLight(Map<String, dynamic> data) async {
    final entities = data.remove('entity_id') as List<String>?;

    if (entities == null || entities.isEmpty) {
      return;
    }

    final serviceData = <String, dynamic>{'entity_id': entities, ...data};

    debugPrint(
      'weather_pro_card light.turn_on: '
      '${jsonEncode(serviceData)}',
    );

    try {
      await widget.conn.callService('light', 'turn_on', serviceData);
    } catch (e) {
      debugPrint('weather_pro_card light control failed: $e');
    }
  }

  Future<void> _setBrightness(double value) async {
    final entities = _entitiesWithCapability((_) => true);

    if (entities.isEmpty) {
      return;
    }

    await _callLight({'entity_id': entities, 'brightness': value.round()});
  }

  Future<void> _setColor(Color color) async {
    final entities = _entitiesWithCapability(
      (modes) =>
          modes.contains('rgb') ||
          modes.contains('rgbw') ||
          modes.contains('rgbww') ||
          modes.contains('hs') ||
          modes.contains('xy'),
    );

    if (entities.isEmpty) {
      return;
    }

    await _callLight({
      'entity_id': entities,
      'rgb_color': [color.r * 255.0, color.g * 255.0, color.b * 255.0],
    });
  }

  Future<void> _setTemperature(double value) async {
    final entities = _entitiesWithCapability(
      (modes) =>
          modes.contains('color_temp') ||
          modes.contains('rgbw') ||
          modes.contains('rgbww'),
    );

    if (entities.isEmpty) {
      return;
    }

    await _callLight({
      'entity_id': entities,
      'color_temp_kelvin': value.round(),
    });
  }

  Future<void> _setEffect(String effect) async {
    final entities = <String>[];

    for (final entity in widget.entities) {
      final state = widget.states.get(entity);

      if (state is! HaState) {
        continue;
      }

      final effects = state.attributes['effect_list'];

      if (effects is List &&
          effects.map((e) => e.toString()).contains(effect)) {
        entities.add(entity);
      }
    }

    if (entities.isEmpty) {
      return;
    }

    await _callLight({'entity_id': entities, 'effect': effect});
  }

  String? _currentEffect() {
    String? current;

    for (final state in _states()) {
      final value = state.attributes['effect']?.toString().trim();

      if (value == null || value.isEmpty || value == 'null') {
        return null;
      }

      if (current == null) {
        current = value;
      } else if (current != value) {
        return null;
      }
    }

    return current;
  }

  Future<void> _showControlDialog() async {
    if (!mounted) {
      return;
    }

    final modes = _colorModes();
    final hasColor = _supportsColor();
    final hasTemperature = _supportsTemperature();
    final effects = _effectList();
          final currentEffect = _currentEffect();

    var brightness = _brightness().toDouble();

    var red = _red().toDouble();
    var green = _green().toDouble();
    var blue = _blue().toDouble();

    final minTemperature = _minColorTemperature();

    final maxTemperature = _maxColorTemperature();

    var temperature = _colorTemperature()
        .clamp(minTemperature, maxTemperature)
        .toDouble();

    final colors = <Color>[
      Colors.white,
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.cyan,
      Colors.blue,
      Colors.purple,
      Colors.pink,
    ];

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .70),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final selectedColor = Color.fromARGB(
              255,
              red.round().clamp(0, 255),
              green.round().clamp(0, 255),
              blue.round().clamp(0, 255),
            );

            return AlertDialog(
              backgroundColor: const Color(0xFF181818),
              surfaceTintColor: Colors.transparent,
              title: Row(
                children: [
                  Icon(mdi(widget.icon), color: Colors.white, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Puissance',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.brightness_low,
                            color: Colors.white70,
                          ),
                          Expanded(
                            child: Slider(
                              value: brightness,
                              min: 1,
                              max: 255,
                              divisions: 254,
                              onChanged: (value) {
                                setDialogState(() {
                                  brightness = value;
                                });

                                _setBrightness(value);
                              },
                            ),
                          ),
                          SizedBox(
                            width: 52,
                            child: Text(
                              '${(brightness / 255 * 100).round()} %',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (hasColor) ...[
                        const SizedBox(height: 18),
                        const Text(
                          'Couleur',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),

                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final color in colors)
                              GestureDetector(
                                onTap: () {
                                  setDialogState(() {
                                    red = color.r * 255.0.toDouble();
                                    green = color.g * 255.0.toDouble();
                                    blue = color.b * 255.0.toDouble();
                                  });

                                  _setColor(color);
                                },
                                child: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: color,
                                    border: Border.all(
                                      color: Colors.white,
                                      width:
                                          selectedColor.toARGB32() ==
                                              color.toARGB32()
                                          ? 3
                                          : 1,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        _rgbSlider(context, 'R', red, Colors.red, (value) {
                          setDialogState(() {
                            red = value;
                          });

                          _setColor(
                            Color.fromARGB(
                              255,
                              value.round(),
                              green.round(),
                              blue.round(),
                            ),
                          );
                        }),

                        _rgbSlider(context, 'G', green, Colors.green, (value) {
                          setDialogState(() {
                            green = value;
                          });

                          _setColor(
                            Color.fromARGB(
                              255,
                              red.round(),
                              value.round(),
                              blue.round(),
                            ),
                          );
                        }),

                        _rgbSlider(context, 'B', blue, Colors.blue, (value) {
                          setDialogState(() {
                            blue = value;
                          });

                          _setColor(
                            Color.fromARGB(
                              255,
                              red.round(),
                              green.round(),
                              value.round(),
                            ),
                          );
                        }),
                      ],

                      if (hasTemperature) ...[
                        const SizedBox(height: 18),
                        const Text(
                          'Température de couleur',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.thermostat, color: Colors.white70),
                            Expanded(
                              child: Slider(
                                value: temperature.clamp(
                                  minTemperature.toDouble(),
                                  maxTemperature.toDouble(),
                                ),
                                min: minTemperature.toDouble(),
                                max: maxTemperature.toDouble(),
                                onChanged: (value) {
                                  setDialogState(() {
                                    temperature = value;
                                  });

                                  _setTemperature(value);
                                },
                              ),
                            ),
                            SizedBox(
                              width: 70,
                              child: Text(
                                '${temperature.round()} K',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      if (effects.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const Text(
                          'Effet',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: effects.contains(currentEffect)
                              ? currentEffect
                              : null,
                          dropdownColor: const Color(0xFF282828),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFF282828),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          hint: const Text(
                            'Choisir un effet',
                            style: TextStyle(color: Colors.white70),
                          ),
                          items: [
                            for (final effect in effects)
                              DropdownMenuItem(
                                value: effect,
                                child: Text(effect),
                              ),
                          ],
                          onChanged: (effect) {
                            if (effect != null) {
                              _setEffect(effect);
                            }
                          },
                        ),
                      ],

                      if (!hasColor && !hasTemperature && effects.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Cette lampe ne propose aucun réglage avancé.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        ),

                      if (modes.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Modes : ${modes.join(', ')}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text(
                    'FERMER',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _rgbSlider(
    BuildContext context,
    String label,
    double value,
    Color color,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0, 255),
            min: 0,
            max: 255,
            divisions: 255,
            activeColor: color,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            value.round().toString(),
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Future<void> _turnOffWithLastState() async {
    debugPrint(
      'weather_pro_card: save last state + turn off: '
      '${jsonEncode(widget.entities)}',
    );

    try {
      await widget.conn.callService(
        'script',
        'light_turn_off_save_last_state',
        {
          'entity_id': widget.entities,
        },
      );
    } catch (e) {
      debugPrint(
        'weather_pro_card save last state + turn off failed: $e',
      );
    }
  }

  Future<void> _restoreLastState() async {
    debugPrint(
      'weather_pro_card: restore last state: '
      '${jsonEncode(widget.entities)}',
    );

    try {
      await widget.conn.callService(
        'script',
        'light_restore_last_state',
        {
          'entity_id': widget.entities,
        },
      );
    } catch (e) {
      debugPrint(
        'weather_pro_card restore last state failed: $e',
      );
    }
  }

  Widget _button(bool on) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    final isLargePanel = screenWidth >= 600;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(isLargePanel ? 20 : 12),
        onTap: () async {
          if (on) {
            await _turnOffWithLastState();
          } else {
            await _restoreLastState();
          }
        },
        onLongPress: _showControlDialog,
        child: Ink(
          decoration: BoxDecoration(
            color: on ? const Color(0xAAFFFFFF) : const Color(0x66000000),
            borderRadius: BorderRadius.circular(isLargePanel ? 20 : 12),
            border: Border.all(
              color: on ? const Color(0xDDFFFFFF) : const Color(0x66FFFFFF),
              width: on && isLargePanel ? 2 : 1.5,
            ),
            boxShadow: on
                ? [
                    BoxShadow(
                      color: const Color(0x55000000),
                      blurRadius: isLargePanel ? 14 : 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  mdi(widget.icon),
                  size: isLargePanel ? 52 : 27,
                  color: on ? Colors.black87 : Colors.white,
                  shadows: on
                      ? null
                      : const [Shadow(blurRadius: 5, color: Colors.black87)],
                ),
                SizedBox(height: isLargePanel ? 14 : 10),
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: on ? Colors.black87 : Colors.white,
                    fontSize: isLargePanel ? 27 : 18,
                    fontWeight: FontWeight.w700,
                    shadows: on
                        ? null
                        : const [Shadow(blurRadius: 5, color: Colors.black87)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
