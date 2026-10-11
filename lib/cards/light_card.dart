import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/fill_card.dart';
import '../ui/theme.dart';
import '../util/color.dart';
import '../util/icons.dart';
import 'echo.dart';
import 'env.dart';
import 'light_control.dart';
import 'light_controller.dart';

class LightCard extends StatefulWidget {
  const LightCard({super.key, required this.config, required this.env});

  final CardConfig config;
  final PanelEnv env;

  @override
  State<LightCard> createState() => _LightCardState();
}

class _LightCardState extends State<LightCard> with EchoMixin {
  CardConfig get c => widget.config;

  List<String> get entities {
    final configured = c['entities'];

    if (configured is List) {
      final values = configured
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList();

      if (values.isNotEmpty) {
        return values;
      }
    }

    final single = c.str('entity')?.trim();
    return single == null || single.isEmpty ? const [] : [single];
  }

  String get entity => entities.isEmpty ? '' : entities.first;

  int get echoMs => c.intOr('echo_ms', 1500);

  LightController get controller =>
      LightController(env: widget.env, entities: entities);

  List<CardConfig> get presets => c['presets'] is List
      ? c.maps('presets')
      : const [
          {'name': 'Low', 'brightness_pct': 15},
          {'name': 'Mid', 'brightness_pct': 50},
          {'name': 'Full', 'brightness_pct': 100},
        ];

  double _entityValue(HaState? s) {
    if (s == null || !s.isOn) {
      return 0;
    }

    final b = s.numAttr('brightness');

    return b == null ? 1 : (b / 255).clamp(0.0, 1.0);
  }

  double _combinedValue(List<HaState?> states, bool on) {
    if (!on) {
      return 0;
    }

    var value = 0.0;
    for (final state in states) {
      if (state?.isOn ?? false) {
        value = value < _entityValue(state) ? _entityValue(state) : value;
      }
    }
    return value;
  }

  Color _accent(HaState? s) {
    final explicit = parseHex(c.str('accent'));

    if (explicit != null) {
      return explicit;
    }

    if (c.boolOr('follow_color', true) && s != null && s.isOn) {
      final rgb = s.attributes['rgb_color'];

      if (rgb is List && rgb.length >= 3 && rgb.every((x) => x is num)) {
        return readableTint(rgb.cast<num>());
      }
    }

    return Ns.amber;
  }

  /// Restore the saved state when switching on.
  ///
  /// The initial turn_on also provides a fallback for a light that has
  /// never had a state saved by the Home Assistant scripts.
  Future<void> _turnOnRestoringLastState() async {
    await controller.turnOnRestoringLastState();
  }

  /// Save the current state before switching off.
  Future<void> _turnOffSavingLastState() async {
    final saved = await controller.saveAndTurnOff();

    // Do not leave the light on if the script call itself fails.
    if (!saved) {
      await controller.turnOff();
    }
  }

  Future<void> _toggleLight(bool isOn) async {
    if (isOn) {
      await _turnOffSavingLastState();
    } else {
      await _turnOnRestoringLastState();
    }
  }

  Future<void> _commit(double value) async {
    final pct = (value * 100).round();

    if (pct <= 0) {
      await _turnOffSavingLastState();
      return;
    }

    final isOn = controller.states().any((state) => state.isOn);

    if (!isOn) {
      await _turnOnRestoringLastState();
    }

    await controller.turnOn(data: {'brightness_pct': pct});
  }

  Future<void> _applyPreset(CardConfig preset) async {
    final scene = preset['scene'];

    if (scene != null) {
      await widget.env.conn.callService('light_memory', 'activate_scene', {
        'entity_id': scene,
      });
      return;
    }

    final pct = (preset['brightness_pct'] as num?)?.toInt();

    if (pct != null && pct <= 0) {
      await _turnOffSavingLastState();
      holdLocal(0, echoMs);
      return;
    }

    final data = <String, dynamic>{};

    if (pct != null) {
      data['brightness_pct'] = pct;
    }

    for (final key in ['color_temp_kelvin', 'rgb_color', 'effect']) {
      if (preset[key] != null) {
        data[key] = preset[key];
      }
    }

    final hasExplicitAppearance = [
      'color_temp_kelvin',
      'rgb_color',
      'effect',
    ].any((key) => preset[key] != null);

    if (!hasExplicitAppearance) {
      final isOn = controller.states().any((state) => state.isOn);

      if (!isOn) {
        await _turnOnRestoringLastState();
      }

      if (data.isNotEmpty) {
        await controller.turnOn(data: data);
      }
    } else {
      // Explicit preset appearance takes precedence over the saved effect.
      await controller.turnOn(data: data);
    }

    if (pct != null) {
      holdLocal(pct / 100, echoMs);
    }
  }

  Future<void> _openAdvancedControls(HaState? state, String fallbackTitle) {
    return showLightControlDialog(
      context: context,
      label: c.titleOr(fallbackTitle),
      icon: c.str('icon') ?? state?.attr<String>('icon') ?? 'mdi:lightbulb',
      entities: entities,
      env: widget.env,
    );
  }

  @override
  Widget build(BuildContext context) {
    final stateListenables = [
      for (final id in entities) widget.env.states.listen(id),
    ];

    return AnimatedBuilder(
      animation: Listenable.merge(stateListenables),
      builder: (context, _) {
        final states = [
          for (final listenable in stateListenables) listenable.value,
        ];

        final broken =
            states.isEmpty ||
            states.every((state) => state == null || state.isBroken);
        final on = states.any((state) => state?.isOn ?? false);

        HaState? state;
        for (final candidate in states) {
          if (candidate != null && !candidate.isBroken) {
            state ??= candidate;
            if (candidate.isOn) {
              state = candidate;
              break;
            }
          }
        }
        state ??= states.whereType<HaState>().firstOrNull;

        final value = display(_combinedValue(states, on));
        final pct = (value * 100).round();
        final showPresets =
            c.boolOr('show_presets', true) && presets.isNotEmpty;
        final fallbackTitle = entity.isEmpty
            ? 'Light'
            : friendlyName(state, entity);

        return FillCard(
          height: c.numOr('height', 200),
          accent: _accent(state),
          fill: on && !broken ? value : 0,
          fillOpacity: on && !broken ? 1 : 0,
          on: on && !broken,
          broken: broken,
          dragTravel: c['drag_travel'] is num && c.numOr('drag_travel', 0) > 0
              ? c.numOr('drag_travel', 0)
              : null,
          leading: IconBox(
            mdi(
              c.str('icon') ?? state?.attr<String>('icon'),
              on ? MdiIcons.lightbulbOn : MdiIcons.lightbulbOutline,
            ),
            on: on,
          ),
          value: on ? ValueText('$pct', unit: '%') : null,
          title: c.titleOr(fallbackTitle),
          sub: broken ? 'Unavailable' : (on ? 'On · $pct%' : 'Off'),
          chips: showPresets
              ? [
                  for (final preset in presets.take(4))
                    ChipSpec(
                      label:
                          preset.str('name') ?? '${preset['brightness_pct']}%',
                      onTap: () => _applyPreset(preset),
                    ),
                ]
              : const [],
          onTap: () => _toggleLight(on),
          onLongPress: c.str('long_press') == 'none'
              ? null
              : () => _openAdvancedControls(state, fallbackTitle),
          onDragValue: (newValue) {
            dragging = true;
            setLocal(newValue);
          },
          onDragEnd: (newValue) {
            dragging = false;
            holdLocal(newValue, echoMs);
            _commit(newValue);
          },
        );
      },
    );
  }
}
