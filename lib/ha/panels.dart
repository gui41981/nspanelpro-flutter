/// A Home Assistant frontend panel returned by `get_panels`.
class HaPanel {
  const HaPanel({
    required this.id,
    required this.componentName,
    required this.icon,
    required this.title,
    required this.defaultVisible,
    required this.config,
    required this.urlPath,
    required this.requireAdmin,
    required this.configPanelDomain,
    required this.showInSidebar,
  });

  final String id;
  final String componentName;
  final String? icon;
  final String? title;
  final bool defaultVisible;
  final Map<String, dynamic>? config;
  final String urlPath;
  final bool requireAdmin;
  final String? configPanelDomain;
  final bool showInSidebar;

  bool get isLovelace => componentName == 'lovelace';

  bool get isNative =>
      componentName != 'lovelace' &&
      componentName != 'app' &&
      componentName != 'custom';

  factory HaPanel.fromJson(
    String id,
    Map<String, dynamic> json,
  ) {
    final rawConfig = json['config'];

    return HaPanel(
      id: id,
      componentName: json['component_name']?.toString() ?? '',
      icon: _nullableString(json['icon']),
      title: _nullableString(json['title']),
      defaultVisible: json['default_visible'] == true,
      config: rawConfig is Map
          ? rawConfig.cast<String, dynamic>()
          : null,
      urlPath: json['url_path']?.toString() ?? id,
      requireAdmin: json['require_admin'] == true,
      configPanelDomain:
          _nullableString(json['config_panel_domain']),
      showInSidebar: json['show_in_sidebar'] == true,
    );
  }

  static String? _nullableString(dynamic value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  @override
  String toString() {
    return 'HaPanel('
        'id=$id, '
        'componentName=$componentName, '
        'urlPath=$urlPath, '
        'title=$title'
        ')';
  }
}

class HaPanels {
  const HaPanels(this.items);

  final Map<String, HaPanel> items;

  HaPanel? operator [](String id) => items[id];

  bool contains(String id) => items.containsKey(id);

  List<HaPanel> get values => items.values.toList(growable: false);

  HaPanel? byUrlPath(String urlPath) {
    final normalized = urlPath.trim().replaceFirst(
      RegExp(r'^/+'),
      '',
    );

    for (final panel in items.values) {
      if (panel.urlPath == normalized) {
        return panel;
      }
    }

    return null;
  }

  HaPanel? byComponentName(String componentName) {
    final normalized = componentName.trim();

    for (final panel in items.values) {
      if (panel.componentName == normalized) {
        return panel;
      }
    }

    return null;
  }

  /// Resolves a stable logical panel name to the actual HA panel.
  ///
  /// Logical names are an application-level vocabulary. The actual panel
  /// remains entirely owned by Home Assistant and is looked up dynamically
  /// from `get_panels`.
  HaPanel? byLogicalName(String name) {
    final normalized = name.trim().toLowerCase();

    switch (normalized) {
      case 'overview':
        return byComponentName('lovelace');

      case 'lights':
      case 'light':
        return byComponentName('light');

      case 'security':
        return byComponentName('security');

      case 'climate':
        return byComponentName('climate');

      case 'energy':
        return byComponentName('energy');

      case 'maintenance':
        return byComponentName('maintenance');

      default:
        return this[normalized] ?? byUrlPath(normalized);
    }
  }

  factory HaPanels.fromJson(Map<String, dynamic> json) {
    final result = <String, HaPanel>{};

    for (final entry in json.entries) {
      final value = entry.value;

      if (value is! Map) {
        continue;
      }

      result[entry.key] = HaPanel.fromJson(
        entry.key,
        value.cast<String, dynamic>(),
      );
    }

    return HaPanels(result);
  }

  @override
  String toString() => 'HaPanels(${items.length} panels)';
}
