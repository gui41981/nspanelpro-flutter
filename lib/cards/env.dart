import '../config/settings.dart';
import '../ha/connection.dart';
import '../ha/panels.dart';
import '../ha/states.dart';

class PanelEnv {
  const PanelEnv({
    required this.states,
    required this.conn,
    required this.settings,
    this.panels,
    this.play,
  });

  final HaStates states;
  final HaConnection conn;
  final Settings settings;
  final HaPanels? panels;
  final void Function(String ref)? play;
}
