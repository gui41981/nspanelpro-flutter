import 'dart:math' as math;

import '../ha/states.dart';
import 'env.dart';

/// Home Assistant is the source of truth for states and capabilities.
/// Group capabilities and effects must be supported by every entity.
class LightController {
  const LightController({required this.env, required this.entities});

  final PanelEnv env;
  final List<String> entities;

  List<HaState> states() =>
      entities.map(env.states.get).whereType<HaState>().toList();

  List<HaState?> _orderedStates() =>
      entities.map((entity) => env.states.get(entity)).toList(growable: false);

  Set<String> _modes(HaState? state) {
    final value = state?.attributes['supported_color_modes'];
    if (value is! List) return <String>{};

    return value
        .map((v) => v.toString().trim())
        .where((v) => v.isNotEmpty)
        .toSet();
  }

  /// Returns only the exact color modes supported by every entity.
  Set<String> colorModes() {
    if (entities.isEmpty) return <String>{};

    Set<String>? common;
    for (final entity in entities) {
      final state = env.states.get(entity);
      if (state == null || state.isBroken) return <String>{};

      final modes = _modes(state);
      common = common == null ? modes : common.intersection(modes);
    }

    return common ?? <String>{};
  }

  bool _everyEntity(bool Function(HaState state) predicate) {
    if (entities.isEmpty) return false;

    for (final entity in entities) {
      final state = env.states.get(entity);
      if (state == null || state.isBroken || !predicate(state)) return false;
    }

    return true;
  }

  bool supportsBrightness() => _everyEntity((state) {
        return _modes(state).any((mode) => mode != 'onoff');
      });

  bool supportsColor() {
    const supportedColorModes = {'rgb', 'rgbw', 'rgbww', 'hs', 'xy'};
    return _everyEntity(
      (state) => _modes(state).any(supportedColorModes.contains),
    );
  }

  bool supportsTemperature() =>
      _everyEntity((state) => _modes(state).contains('color_temp'));

  /// Only effects supported by every entity are offered for a group.
  List<String> effectList() {
    if (entities.isEmpty) return <String>[];

    Set<String>? common;
    for (final entity in entities) {
      final state = env.states.get(entity);
      if (state == null || state.isBroken) return <String>[];

      final value = state.attributes['effect_list'];
      final effects = value is List
          ? value
              .map((v) => v.toString().trim())
              .where((v) => v.isNotEmpty)
              .toSet()
          : <String>{};

      common = common == null ? effects : common.intersection(effects);
    }

    return (common ?? <String>{}).toList()..sort();
  }

  /// Kept for callers that need individual capability checks.
  List<String> entitiesWithCapability(
    bool Function(Set<String> modes) predicate,
  ) {
    return entities.where((entity) {
      final state = env.states.get(entity);
      return state != null && !state.isBroken && predicate(_modes(state));
    }).toList();
  }

  int brightness() => commonBrightness() ?? 255;

  int? commonBrightness() => _commonNumericAttribute(
        'brightness',
        (value) => value.round().clamp(1, 255).toInt(),
      );

  int red() => commonRgbComponent(0) ?? 255;
  int green() => commonRgbComponent(1) ?? 255;
  int blue() => commonRgbComponent(2) ?? 255;

  /// Resolves RGB from whichever color representation HA exposes.
  /// RGB values are compared across entities only after conversion.
  List<int>? _rgbFromState(HaState? state) {
    if (state == null || state.isBroken) return null;
    final attributes = state.attributes;

    for (final key in const ['rgb_color', 'rgbw_color', 'rgbww_color']) {
      final value = attributes[key];
      if (value is List &&
          value.length >= 3 &&
          value[0] is num &&
          value[1] is num &&
          value[2] is num) {
        return [
          (value[0] as num).round().clamp(0, 255).toInt(),
          (value[1] as num).round().clamp(0, 255).toInt(),
          (value[2] as num).round().clamp(0, 255).toInt(),
        ];
      }
    }

    final hs = attributes['hs_color'];
    if (hs is List && hs.length >= 2 && hs[0] is num && hs[1] is num) {
      return _hsToRgb(
        (hs[0] as num).toDouble(),
        (hs[1] as num).toDouble(),
      );
    }

    final xy = attributes['xy_color'];
    if (xy is List && xy.length >= 2 && xy[0] is num && xy[1] is num) {
      return _xyToRgb(
        (xy[0] as num).toDouble(),
        (xy[1] as num).toDouble(),
      );
    }

    return null;
  }

  List<int> _hsToRgb(double hue, double saturation) {
    final h = ((hue % 360) + 360) % 360;
    final s = (saturation / 100).clamp(0.0, 1.0);
    final chroma = s;
    final x = chroma * (1 - (((h / 60) % 2) - 1).abs());
    final m = 1 - chroma;

    late double r;
    late double g;
    late double b;

    if (h < 60) {
      r = chroma;
      g = x;
      b = 0;
    } else if (h < 120) {
      r = x;
      g = chroma;
      b = 0;
    } else if (h < 180) {
      r = 0;
      g = chroma;
      b = x;
    } else if (h < 240) {
      r = 0;
      g = x;
      b = chroma;
    } else if (h < 300) {
      r = x;
      g = 0;
      b = chroma;
    } else {
      r = chroma;
      g = 0;
      b = x;
    }

    return [
      ((r + m) * 255).round().clamp(0, 255).toInt(),
      ((g + m) * 255).round().clamp(0, 255).toInt(),
      ((b + m) * 255).round().clamp(0, 255).toInt(),
    ];
  }

  List<int>? _xyToRgb(double x, double y) {
    if (!x.isFinite || !y.isFinite || y <= 0 || x < 0 || x > 1 || y > 1) {
      return null;
    }

    // Convert CIE xy to XYZ with Y=1, then XYZ to linear sRGB.
    final X = x / y;
    const Y = 1.0;
    final Z = (1 - x - y) / y;

    var r = 3.2406 * X - 1.5372 * Y - 0.4986 * Z;
    var g = -0.9689 * X + 1.8758 * Y + 0.0415 * Z;
    var b = 0.0557 * X - 0.2040 * Y + 1.0570 * Z;

    r = math.max(0.0, r);
    g = math.max(0.0, g);
    b = math.max(0.0, b);

    final peak = math.max(r, math.max(g, b));
    if (peak <= 0) return null;

    // Normalize to the brightest representable sRGB value.
    r /= peak;
    g /= peak;
    b /= peak;

    double gamma(double value) {
      if (value <= 0.0031308) return 12.92 * value;
      return 1.055 * math.pow(value, 1 / 2.4).toDouble() - 0.055;
    }

    return [
      (gamma(r) * 255).round().clamp(0, 255).toInt(),
      (gamma(g) * 255).round().clamp(0, 255).toInt(),
      (gamma(b) * 255).round().clamp(0, 255).toInt(),
    ];
  }

  int? commonRgbComponent(int index) {
    if (index < 0 || index > 2 || entities.isEmpty) return null;

    final values = <int>[];
    for (final state in _orderedStates()) {
      final rgb = _rgbFromState(state);
      if (rgb == null) return null;
      values.add(rgb[index]);
    }

    if (values.isEmpty || values.any((v) => v != values.first)) return null;
    return values.first;
  }

  int colorTemperature() => commonColorTemperature() ?? 4000;

  int? commonColorTemperature() {
    if (entities.isEmpty) return null;

    final values = <int>[];
    for (final state in _orderedStates()) {
      if (state == null || state.isBroken) return null;

      final kelvin = state.attributes['color_temp_kelvin'];
      final mired = state.attributes['color_temp'];

      if (kelvin is num && kelvin > 0) {
        values.add(kelvin.round());
      } else if (mired is num && mired > 0) {
        values.add((1000000 / mired).round());
      } else {
        return null;
      }
    }

    if (values.isEmpty || values.any((v) => v != values.first)) return null;
    return values.first;
  }

  /// A group can only use the overlapping temperature range of its members.
  int minColorTemperature() {
    int? result;

    for (final state in _orderedStates()) {
      if (state == null || state.isBroken) return 2000;

      final value = state.attributes['min_color_temp_kelvin'];
      final current = value is num ? value.round() : 2000;
      if (result == null || current > result) result = current;
    }

    return result ?? 2000;
  }

  int maxColorTemperature() {
    int? result;

    for (final state in _orderedStates()) {
      if (state == null || state.isBroken) return 6500;

      final value = state.attributes['max_color_temp_kelvin'];
      final current = value is num ? value.round() : 6500;
      if (result == null || current < result) result = current;
    }

    return result ?? 6500;
  }

  int? _commonNumericAttribute(
    String attribute,
    int Function(num value) transform,
  ) {
    if (entities.isEmpty) return null;

    final values = <int>[];
    for (final state in _orderedStates()) {
      final value = state?.attributes[attribute];
      if (state == null || state.isBroken || value is! num) return null;
      values.add(transform(value));
    }

    if (values.isEmpty || values.any((v) => v != values.first)) return null;
    return values.first;
  }

  Future<bool> turnOn({
    Iterable<String>? target,
    Map<String, dynamic>? data,
  }) =>
      _call('turn_on', target: target, data: data);

  Future<bool> turnOff({Iterable<String>? target}) =>
      _call('turn_off', target: target);

  Future<bool> toggle({Iterable<String>? target}) =>
      _call('toggle', target: target);

  Future<bool> setBrightness(double value) {
    if (!supportsBrightness()) return Future<bool>.value(false);

    return turnOn(
      data: {'brightness': value.round().clamp(1, 255).toInt()},
    );
  }

  Future<bool> setColor({
    required int red,
    required int green,
    required int blue,
  }) {
    if (!supportsColor()) return Future<bool>.value(false);

    return turnOn(data: {
      'rgb_color': [
        red.clamp(0, 255).toInt(),
        green.clamp(0, 255).toInt(),
        blue.clamp(0, 255).toInt(),
      ],
    });
  }

  Future<bool> setTemperature(int kelvin) {
    if (!supportsTemperature()) return Future<bool>.value(false);

    final min = minColorTemperature();
    final max = maxColorTemperature();
    if (min > max) return Future<bool>.value(false);

    return turnOn(
      data: {'color_temp_kelvin': kelvin.clamp(min, max).toInt()},
    );
  }

  Future<bool> setEffect(String effect) {
    if (!effectList().contains(effect)) return Future<bool>.value(false);
    return turnOn(data: {'effect': effect});
  }

  String? currentEffect() {
    if (entities.isEmpty) return null;

    final values = <String>[];
    for (final state in _orderedStates()) {
      final value = state?.attributes['effect']?.toString().trim();
      if (state == null ||
          state.isBroken ||
          value == null ||
          value.isEmpty ||
          value == 'null') {
        return null;
      }
      values.add(value);
    }

    if (values.isEmpty || values.any((v) => v != values.first)) return null;
    return values.first;
  }

  bool get effectValuesDiffer {
    final values = _orderedStates()
        .map((state) => state?.attributes['effect']?.toString().trim())
        .toList();

    return values.length > 1 && values.any((v) => v != values.first);
  }

  Future<bool> saveAndTurnOff() =>
      env.conn.callService('light_memory', 'turn_off', {
        'entity_id': List<String>.from(entities),
      });

  Future<bool> restoreLastState() =>
      env.conn.callService('light_memory', 'restore', {
        'entity_id': List<String>.from(entities),
      });

  Future<bool> _call(
    String service, {
    Iterable<String>? target,
    Map<String, dynamic>? data,
  }) {
    final targetEntities = target?.toList() ?? entities;
    if (targetEntities.isEmpty) return Future<bool>.value(false);

    return env.conn.callService('light_memory', service, {
      'entity_id': targetEntities,
      ...?data,
    });
  }

  Future<void> turnOnRestoringLastState() async {
    await env.conn.callService('light_memory', 'turn_on', {
      'entity_id': List<String>.from(entities),
    });
  }
}
