import 'dashboard.dart';
import '../ha/panels.dart';

/// The semantic kind of a Lovelace node after parsing.
///
/// Parsing answers "what is in the dashboard?".
/// Resolution answers "what kind of thing is this for the panel?"
enum ResolvedCardKind {
  customCard,
  layout,
  builtInPanel,
  unsupported,
}

/// A dashboard node after semantic classification.
///
/// This deliberately keeps the original [CardConfig]. The resolver does not
/// rewrite Lovelace configuration or duplicate entity state.
class ResolvedCard {
  const ResolvedCard({
    required this.kind,
    required this.config,
    this.type,
    this.panelId,
  });

  final ResolvedCardKind kind;
  final CardConfig config;

  /// Normalized Lovelace type, without the `custom:` prefix.
  final String? type;

  /// HA native panel identifier when this node represents a built-in panel.
  ///
  /// This is intentionally nullable for now because the current dashboard
  /// format does not yet define a panel-reference schema.
  final String? panelId;

  bool get isCustomCard => kind == ResolvedCardKind.customCard;
  bool get isLayout => kind == ResolvedCardKind.layout;
  bool get isBuiltInPanel => kind == ResolvedCardKind.builtInPanel;
  bool get isUnsupported => kind == ResolvedCardKind.unsupported;
}

/// Resolve a Lovelace card into the semantic category understood by the
/// Flutter application.
///
/// Resolution is deliberately conservative:
///
/// 1. explicit custom cards
/// 2. known Lovelace layouts
/// 3. explicit native-panel references
/// 4. unsupported cards
///
/// No entity, device, area or HA state lookup happens here. Those belong to
/// later functional resolution and must never be inferred from this layer.
ResolvedCard resolveCard(
  CardConfig config, {
  HaPanels? panels,
}) {
  final type = cardType(config);

  if (_customCardTypes.contains(type)) {
    return ResolvedCard(
      kind: ResolvedCardKind.customCard,
      config: config,
      type: type,
    );
  }

  if (_layoutTypes.contains(type)) {
    return ResolvedCard(
      kind: ResolvedCardKind.layout,
      config: config,
      type: type,
    );
  }

  final panelId = _panelId(config);
  if (panelId != null) {
    if (panels == null) {
      return ResolvedCard(
        kind: ResolvedCardKind.unsupported,
        config: config,
        type: type.isEmpty ? null : type,
      );
    }

    final panel = panels.byLogicalName(panelId);

    if (panel != null) {
      return ResolvedCard(
        kind: ResolvedCardKind.builtInPanel,
        config: config,
        type: type.isEmpty ? null : type,
        panelId: panel.id,
      );
    }

    return ResolvedCard(
      kind: ResolvedCardKind.unsupported,
      config: config,
      type: type.isEmpty ? null : type,
    );
  }

  return ResolvedCard(
    kind: ResolvedCardKind.unsupported,
    config: config,
    type: type.isEmpty ? null : type,
  );
}

/// Cards that this application renders natively.
///
/// Keep this list as a registry of capabilities, not as a place for entity
/// or room-specific logic.
const Set<String> _customCardTypes = {
  'nspanel-light-card',
  'nspanel-cover-card',
  'nspanel-climate-card',
  'nspanel-media-card',
  'nspanel-switch-card',
  'nspanel-button-card',
  'nspanel-alarm-card',
  'nspanel-sensor-card',
  'nspanel-sensors-card',
  'nspanel-status-card',
  'nspanel-weather-card',
  'nspanel-weather-pro-card',
  'nspanel-clock-card',
  'nspanel-screensaver',
};

const Set<String> _layoutTypes = {
  'vertical-stack',
  'horizontal-stack',
  'grid',
};

/// Explicit native HA panel references.
///
/// This is intentionally a very small contract for now. We do not attempt to
/// guess whether a card belongs to Overview, Lights, Security, Climate, etc.
///
/// Supported forms are:
///
///   type: panel
///   panel: lights
///
/// or:
///
///   type: custom:nspanel-panel
///   panel: lights
///
/// The navigation implementation will be added separately.
String? _panelId(CardConfig config) {
  final explicitPanel = config['panel'];
  if (explicitPanel is String && explicitPanel.trim().isNotEmpty) {
    final type = cardType(config);

    if (type == 'panel' || type == 'nspanel-panel') {
      return explicitPanel.trim();
    }
  }

  return null;
}

/// Whether the application has a native renderer for a card type.
bool isSupportedCustomCard(String type) =>
    _customCardTypes.contains(type);

/// Whether the type is a Lovelace layout handled by the renderer.
bool isSupportedLayout(String type) => _layoutTypes.contains(type);
