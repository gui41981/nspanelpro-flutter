import 'package:flutter/material.dart';

import '../util/icons.dart';
import 'env.dart';
import 'light_controller.dart';

Future<void> showLightControlDialog({
  required BuildContext context,
  required String label,
  required String icon,
  required List<String> entities,
  required PanelEnv env,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .70),
    builder: (_) => _LightControlDialog(
      label: label,
      icon: icon,
      entities: List<String>.from(entities),
      env: env,
    ),
  );
}

class LightControl extends StatefulWidget {
  const LightControl({
    super.key,
    required this.label,
    required this.icon,
    required this.entities,
    required this.env,
  });

  final String label;
  final String icon;
  final List<String> entities;
  final PanelEnv env;

  @override
  State<LightControl> createState() => _LightControlState();
}

class _LightControlState extends State<LightControl> {
  LightController get controller =>
      LightController(env: widget.env, entities: widget.entities);

  Future<void> _showControlDialog() async {
    // Ouvre le dialogue pour visualiser la configuration.
    final dialog = showLightControlDialog(
      context: context,
      label: widget.label,
      icon: widget.icon,
      entities: widget.entities,
      env: widget.env,
    );

    // Restaure la configuration mémorisée sans demander l'allumage.
    await controller.restoreLastState();

    await dialog;
  }

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[
      for (final entity in widget.entities) widget.env.states.listen(entity),
    ];

    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        final on = widget.entities.any(
          (entity) => widget.env.states.get(entity)?.isOn == true,
        );
        final large = MediaQuery.sizeOf(context).width >= 600;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(large ? 20 : 12),
            onTap: () async {
              if (on) {
                await controller.saveAndTurnOff();
              } else {
                await controller.turnOnRestoringLastState();
              }
            },
            onLongPress: _showControlDialog,
            child: Ink(
              decoration: BoxDecoration(
                color: on
                    ? const Color(0xAAFFFFFF)
                    : const Color(0x66000000),
                borderRadius: BorderRadius.circular(large ? 20 : 12),
                border: Border.all(
                  color: on
                      ? const Color(0xDDFFFFFF)
                      : const Color(0x66FFFFFF),
                  width: on && large ? 2 : 1.5,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      mdi(widget.icon),
                      size: large ? 52 : 27,
                      color: on ? Colors.black87 : Colors.white,
                    ),
                    SizedBox(height: large ? 14 : 10),
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: on ? Colors.black87 : Colors.white,
                        fontSize: large ? 27 : 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LightControlDialog extends StatefulWidget {
  const _LightControlDialog({
    required this.label,
    required this.icon,
    required this.entities,
    required this.env,
  });

  final String label;
  final String icon;
  final List<String> entities;
  final PanelEnv env;

  @override
  State<_LightControlDialog> createState() => _LightControlDialogState();
}

class _LightControlDialogState extends State<_LightControlDialog> {
  LightController get controller =>
      LightController(env: widget.env, entities: widget.entities);

  Future<void> _setBrightness(double value) =>
      controller.setBrightness(value);

  Future<void> _setColor(Color color) => controller.setColor(
        red: (color.r * 255).round(),
        green: (color.g * 255).round(),
        blue: (color.b * 255).round(),
      );

  Future<void> _setTemperature(double value) =>
      controller.setTemperature(value.round());

  Future<void> _setEffect(String effect) => controller.setEffect(effect);

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 5),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
      );

  Widget _rgbSlider(
    String label,
    double value,
    Color color,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 22,
          child: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, 255.0).toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            activeColor: color,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            value.round().toString(),
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[
      for (final entity in widget.entities) widget.env.states.listen(entity),
    ];

    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        final c = controller;
        final states = c.states();
        final isGroup = widget.entities.length > 1;
        final available = states.length == widget.entities.length &&
            states.every((state) => !state.isBroken);
        final anyOn = states.any((state) => state.isOn);
        final allOn = states.isNotEmpty && states.every((state) => state.isOn);
        final singleState = states.isEmpty ? null : states.first;

        final String status;
        if (!available) {
          status = 'État indisponible';
        } else if (!isGroup) {
          status = singleState?.isOn == true ? 'Lampe allumée' : 'Lampe éteinte';
        } else if (allOn) {
          status = 'Toutes les lampes sont allumées';
        } else if (!anyOn) {
          status = 'Groupe éteint';
        } else {
          status = 'État mixte : certaines lampes sont allumées';
        }

        final hasBrightness = c.supportsBrightness();
        final hasColor = c.supportsColor();
        final hasTemperature = c.supportsTemperature();
        final effects = c.effectList();
        final currentEffect = c.currentEffect();

        final brightness = c.commonBrightness();
        final red = c.commonRgbComponent(0);
        final green = c.commonRgbComponent(1);
        final blue = c.commonRgbComponent(2);
        final temperature = c.commonColorTemperature();

        final minTemp = c.minColorTemperature();
        final maxTemp = c.maxColorTemperature();
        final validTempRange = minTemp <= maxTemp;
        final safeMaxTemp = validTempRange ? maxTemp : minTemp + 1;
        final sliderTemp =
            (temperature ?? minTemp).clamp(minTemp, safeMaxTemp).toDouble();

        final modes = c.colorModes().toList()..sort();
        final screenWidth = MediaQuery.sizeOf(context).width;

        return AlertDialog(
          backgroundColor: const Color(0xFF202126),
          titlePadding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
          contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          title: Row(
            children: [
              Icon(mdi(widget.icon), color: Colors.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Fermer',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          content: SizedBox(
            width: screenWidth >= 700 ? 560 : screenWidth * .88,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          status,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      TextButton(
                        onPressed: !available
                            ? null
                            : () async {
                                if (anyOn) {
                                  await c.saveAndTurnOff();
                                } else {
                                  await c.turnOnRestoringLastState();
                                }
                              },
                        child: Text(
                          isGroup
                              ? (anyOn ? 'Tout éteindre' : 'Tout allumer')
                              : (anyOn ? 'Éteindre' : 'Allumer'),
                        ),
                      ),
                    ],
                  ),
                  if (!available)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'État indisponible pour au moins une lampe.',
                        style: TextStyle(color: Colors.orangeAccent),
                      ),
                    ),
                  if (hasBrightness) ...[
                    _sectionTitle('Luminosité'),
                    if (brightness == null)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Valeurs différentes ou non disponibles',
                          style: TextStyle(color: Colors.white60),
                        ),
                      ),
                    Slider(
                      value: (brightness ?? 128).toDouble(),
                      min: 1,
                      max: 255,
                      divisions: 254,
                      label: brightness == null
                          ? 'Valeurs différentes'
                          : '${(brightness / 255 * 100).round()} %',
                      onChanged: (value) {
                        _setBrightness(value);
                      },
                    ),
                    if (brightness != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${(brightness / 255 * 100).round()} %',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                  ],
                  if (hasColor) ...[
                    _sectionTitle('Couleur'),
                    if (red == null || green == null || blue == null)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Couleurs différentes ou non disponibles',
                          style: TextStyle(color: Colors.white60),
                        ),
                      ),
                    _rgbSlider(
                      'R',
                      (red ?? 128).toDouble(),
                      Colors.redAccent,
                      (value) => _setColor(Color.fromARGB(
                        255,
                        value.round(),
                        green ?? 128,
                        blue ?? 128,
                      )),
                    ),
                    _rgbSlider(
                      'G',
                      (green ?? 128).toDouble(),
                      Colors.greenAccent,
                      (value) => _setColor(Color.fromARGB(
                        255,
                        red ?? 128,
                        value.round(),
                        blue ?? 128,
                      )),
                    ),
                    _rgbSlider(
                      'B',
                      (blue ?? 128).toDouble(),
                      Colors.lightBlueAccent,
                      (value) => _setColor(Color.fromARGB(
                        255,
                        red ?? 128,
                        green ?? 128,
                        value.round(),
                      )),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final color in const [
                          Colors.white,
                          Colors.red,
                          Colors.orange,
                          Colors.yellow,
                          Colors.green,
                          Colors.cyan,
                          Colors.blue,
                          Colors.purple,
                          Colors.pink,
                        ])
                          InkWell(
                            onTap: () => _setColor(color),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white70),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (hasTemperature && validTempRange) ...[
                    _sectionTitle('Température de couleur'),
                    if (temperature == null)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Valeurs différentes ou non disponibles',
                          style: TextStyle(color: Colors.white60),
                        ),
                      ),
                    Slider(
                      value: sliderTemp,
                      min: minTemp.toDouble(),
                      max: safeMaxTemp.toDouble(),
                      divisions: safeMaxTemp - minTemp > 1
                          ? safeMaxTemp - minTemp
                          : null,
                      label: temperature == null
                          ? 'Valeurs différentes'
                          : '$temperature K',
                      onChanged: _setTemperature,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        temperature == null
                            ? '$minTemp–$maxTemp K'
                            : '$temperature K',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                  if (effects.isNotEmpty) ...[
                    _sectionTitle('Effet lumineux'),
                    DropdownButtonFormField<String>(
                      initialValue: currentEffect != null &&
                              effects.contains(currentEffect)
                          ? currentEffect
                          : null,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF303138),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF303138),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        hintText: c.effectValuesDiffer
                            ? 'Effets différents'
                            : (isGroup
                                ? 'Aucun effet commun sélectionné'
                                : 'Choisir un effet'),
                      ),
                      items: [
                        for (final effect in effects)
                          DropdownMenuItem(
                            value: effect,
                            child: Text(
                              effect,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (effect) {
                        if (effect != null) _setEffect(effect);
                      },
                    ),
                  ],
                  if (isGroup && modes.isNotEmpty) ...[
                    _sectionTitle('Modes communs'),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        modes.join(' · '),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  if (!hasBrightness &&
                      !hasColor &&
                      !hasTemperature &&
                      effects.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'Aucun réglage avancé commun à toutes les lampes.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }
}
