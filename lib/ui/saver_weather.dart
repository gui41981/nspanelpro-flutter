import 'dart:async';

import 'package:flutter/material.dart';

import '../cards/env.dart';
import '../ha/connection.dart';
import '../ha/states.dart';
import '../util/fmt.dart';
import '../util/icons.dart';
import '../util/weather.dart';

/// The weather under the screensaver clock: the condition and the
/// temperature now, and - when [forecast] - today's high and low and the
/// chance of rain from the daily forecast.
///
/// The screensaver can stand for hours, so the current conditions follow the
/// entity like any card, and the forecast is one websocket subscription for
/// as long as the screensaver is up, dropped when it goes.
class SaverWeather extends StatefulWidget {
  const SaverWeather({
    super.key,
    required this.entity,
    required this.env,
    this.forecast = true,
    this.size = 64,
  });
  final String entity;
  final PanelEnv env;
  final bool forecast;

  /// The clock's digit height, so the weather scales with the clock.
  final double size;

  @override
  State<SaverWeather> createState() => _SaverWeatherState();
}

class _SaverWeatherState extends State<SaverWeather> {
  Map<dynamic, dynamic>? _today;
  Future<void> Function()? _unsub;
  int? _subscribedGeneration;
  int? _subscribingGeneration;
  int _subscriptionRevision = 0;

  @override
  void initState() {
    super.initState();
    widget.env.conn.generationListenable.addListener(_onGenerationChanged);
    _maybeSubscribe();
  }

  @override
  void didUpdateWidget(covariant SaverWeather oldWidget) {
    super.didUpdateWidget(oldWidget);

    final changed = oldWidget.entity != widget.entity ||
        oldWidget.forecast != widget.forecast ||
        oldWidget.env.conn != widget.env.conn;

    if (oldWidget.env.conn != widget.env.conn) {
      oldWidget.env.conn.generationListenable.removeListener(
        _onGenerationChanged,
      );
      widget.env.conn.generationListenable.addListener(_onGenerationChanged);
    }

    if (changed) _resetSubscription();
  }

  @override
  void dispose() {
    _subscriptionRevision++;
    widget.env.conn.generationListenable.removeListener(_onGenerationChanged);
    _unsub?.call();
    super.dispose();
  }

  void _resetSubscription() {
    // A pending subscribe must not resurrect the old entity's callback.
    _subscriptionRevision++;
    final unsubscribe = _unsub;
    _unsub = null;
    _subscribedGeneration = null;
    _today = null;
    if (unsubscribe != null) unawaited(unsubscribe());
    _maybeSubscribe();
  }

  void _onGenerationChanged() {
    // Subscriptions belong to a socket; the old socket is already gone.
    _subscriptionRevision++;
    _unsub = null;
    _subscribedGeneration = null;
    if (mounted && _today != null) setState(() => _today = null);
    _maybeSubscribe();
  }

  Future<void> _maybeSubscribe() async {
    if (!widget.forecast) return;

    final conn = widget.env.conn;
    final generation = conn.generation;
    final revision = _subscriptionRevision;
    final subscribedEntity = widget.entity;
    if (conn.status.value != HaStatus.online || generation == 0) return;

    if (_subscribedGeneration == generation ||
        _subscribingGeneration == generation) {
      return;
    }

    _subscribingGeneration = generation;
    try {
      final unsubscribe = await conn.subscribe({
        'type': 'weather/subscribe_forecast',
        'forecast_type': 'daily',
        'entity_id': subscribedEntity,
      }, (ev) {
        final list = (ev as Map?)?['forecast'] as List?;
        if (!mounted ||
            revision != _subscriptionRevision ||
            conn.generation != generation ||
            list == null ||
            list.isEmpty ||
            list.first is! Map) {
          return;
        }
        setState(() => _today = list.first as Map);
      });

      if (!mounted ||
          revision != _subscriptionRevision ||
          conn.generation != generation ||
          conn.status.value != HaStatus.online) {
        await unsubscribe();
        return;
      }

      _unsub = unsubscribe;
      _subscribedGeneration = generation;
    } catch (_) {
      // an old core, or a provider without a daily forecast: the attribute,
      // or just the current conditions
    } finally {
      if (_subscribingGeneration == generation) {
        _subscribingGeneration = null;
      }
      if (mounted && revision != _subscriptionRevision) {
        _maybeSubscribe();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.size / 64;
    const shadow = [
      Shadow(offset: Offset(0, 1), blurRadius: 4, color: Color(0x80000000)),
    ];
    return ValueListenableBuilder<HaState?>(
      valueListenable: widget.env.states.listen(widget.entity),
      builder: (context, s, _) {
        if (s == null || s.isBroken) return const SizedBox.shrink();
        final temp = s.numAttr('temperature');
        final unit = s.attr<String>('temperature_unit') ?? '°';
        final rainUnit = s.attr<String>('precipitation_unit') ?? 'mm';
        final fallback = s.attributes['forecast'];
        final today =
            _today ??
            (widget.forecast &&
                    fallback is List &&
                    fallback.isNotEmpty &&
                    fallback.first is Map
                ? fallback.first as Map
                : null);

        final second = <String>[];
        if (today != null) {
          final hi = today['temperature'];
          final lo = today['templow'];
          if (hi is num && lo is num) {
            second.add('${fmt(hi, 0)}° / ${fmt(lo, 0)}°');
          } else if (hi is num) {
            second.add('${fmt(hi, 0)}°');
          }
          final rain = rainOf(today, unit: rainUnit);
          if (rain != null && rain.wet) second.add('${rain.text} rain');
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  mdi(weatherIcons[s.state] ?? 'mdi:weather-cloudy'),
                  size: 22 * k,
                  color: Colors.white,
                  shadows: shadow,
                ),
                SizedBox(width: 8 * k),
                Flexible(
                  child: Text(
                    [
                      if (temp != null)
                        '${fmt(temp, 0)}${unit.startsWith('°') ? '°' : ' $unit'}',
                      conditionLabel(s.state),
                    ].join('  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17 * k,
                      fontWeight: FontWeight.w600,
                      shadows: shadow,
                    ),
                  ),
                ),
              ],
            ),
            if (second.isNotEmpty) ...[
              SizedBox(height: 2 * k),
              Text(
                second.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .8),
                  fontSize: 14 * k,
                  fontWeight: FontWeight.w500,
                  shadows: shadow,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
