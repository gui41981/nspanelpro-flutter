import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/cards/button_card.dart';
import 'package:nspanel_app/cards/env.dart';
import 'package:nspanel_app/config/settings.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/states.dart';

import 'connection_test.dart' show FakeHa, st;

void main() {
  testWidgets('lit by another entity, in its own colour, icon only', (
    tester,
  ) async {
    late FakeHa fake;
    late HaStates states;
    late HaConnection conn;
    await tester.runAsync(() async {
      fake = FakeHa({
        'script.movie': st('script.movie', 'off', {
          'friendly_name': 'Movie mode',
        }),
        'input_boolean.movie': st('input_boolean.movie', 'on', {}),
        'script.normal': st('script.normal', 'off', {'friendly_name': 'Normal'}),
      });
      states = HaStates();
      conn = HaConnection(
        transportFactory: () async => fake,
        token: 'good',
        states: states,
      );
      final ready = Completer<void>();
      conn.onReady = ready.complete;
      await conn.start();
      await ready.future.timeout(const Duration(seconds: 2));
    });
    final env = PanelEnv(
      states: states,
      conn: conn,
      settings: Settings(url: 'http://x', token: 't'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ButtonCard(
            config: {
              'type': 'custom:nspanel-button-card',
              'height': 200,
              'show_name': false,
              'buttons': [
                {
                  'entity': 'script.movie',
                  'icon': 'mdi:movie-open',
                  'state_entity': 'input_boolean.movie',
                  'color': '#a78bfa',
                },
                {
                  'entity': 'script.normal',
                  'icon': 'mdi:skip-backward',
                  'show_name': true,
                },
              ],
            },
            env: env,
          ),
        ),
      ),
    );
    await tester.pump();
    // icon only on the first, the second asked for its name back
    expect(find.text('Movie mode'), findsNothing);
    expect(find.text('Normal'), findsOneWidget);
    // lit by the boolean, in violet, while its own script is off
    final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
    expect(icons.first.color, const Color(0xFFA78BFA));
    expect(
      icons.first.size,
      48,
      reason: 'the icon takes the room the name had',
    );
    expect(icons.last.color, isNot(const Color(0xFFA78BFA)));

    // the boolean goes off: the button goes dark
    fake.states['input_boolean.movie']!['state'] = 'off';
    fake.push('input_boolean.movie');
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester.widgetList<Icon>(find.byType(Icon)).first.color,
      isNot(const Color(0xFFA78BFA)),
    );
    unawaited(conn.dispose());
  });
  testWidgets('button card replaces its items when dashboard config changes', (
    tester,
  ) async {
    late FakeHa fake;
    late HaStates states;
    late HaConnection conn;
    await tester.runAsync(() async {
      fake = FakeHa({
        'script.first': st('script.first', 'off', {'friendly_name': 'First'}),
        'script.second': st('script.second', 'off', {'friendly_name': 'Second'}),
      });
      states = HaStates();
      conn = HaConnection(
        transportFactory: () async => fake,
        token: 'good',
        states: states,
      );
      final ready = Completer<void>();
      conn.onReady = ready.complete;
      await conn.start();
      await ready.future.timeout(const Duration(seconds: 2));
    });
    final env = PanelEnv(
      states: states,
      conn: conn,
      settings: Settings(url: 'http://x', token: 't'),
    );

    Widget panel(String entity, String name) => MaterialApp(
      home: Scaffold(
        body: ButtonCard(
          config: {
            'type': 'custom:nspanel-button-card',
            'buttons': [{'entity': entity, 'name': name}],
          },
          env: env,
        ),
      ),
    );

    await tester.pumpWidget(panel('script.first', 'First'));
    expect(find.text('First'), findsOneWidget);
    await tester.pumpWidget(panel('script.second', 'Second'));
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pumpEventQueue();
    await tester.runAsync(conn.dispose);
  });

}
