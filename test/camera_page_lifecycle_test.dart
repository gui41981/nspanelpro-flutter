import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/cards/camera_card.dart';
import 'package:nspanel_app/cards/camera_live_view.dart';
import 'package:nspanel_app/cards/env.dart';
import 'package:nspanel_app/config/settings.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/states.dart';
import 'package:nspanel_app/ui/page_scope.dart';

import 'connection_test.dart' show FakeHa;

void main() {
  testWidgets('native live camera is mounted only on the visible awake page', (
    tester,
  ) async {
    final fake = FakeHa({});
    final states = HaStates();
    final conn = HaConnection(
      transportFactory: () async => fake,
      token: 'good',
      states: states,
    );
    final shown = ValueNotifier<int>(0);
    final awake = ValueNotifier<bool>(true);
    final env = PanelEnv(
      states: states,
      conn: conn,
      settings: Settings(url: 'http://x', token: 't'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageScope(
            index: 2,
            shown: shown,
            awake: awake,
            child: CameraCard(
              config: {
                'type': 'custom:nspanel-camera-card',
                'entity': 'camera.bedroom_fluent',
                'camera_view': 'live',
              },
              env: env,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Camera paused'), findsOneWidget);
    expect(find.byType(CameraLiveView), findsNothing);

    shown.value = 2;
    await tester.pump();
    expect(find.byType(CameraLiveView), findsOneWidget);

    awake.value = false;
    await tester.pump();
    expect(find.text('Camera paused'), findsOneWidget);
    expect(find.byType(CameraLiveView), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await conn.dispose();
    shown.dispose();
    awake.dispose();
  });
}
