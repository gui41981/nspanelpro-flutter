/// A card config is the same map Lovelace holds.
///
/// The parser keeps the original dashboard structure as configuration.
/// Semantic interpretation belongs to the resolution layer.
typedef CardConfig = Map<String, dynamic>;

class PanelPage {
  const PanelPage(this.cards);

  final List<CardConfig> cards;
}

/// `custom:nspanel-light-card` -> `nspanel-light-card`.
String cardType(CardConfig c) =>
    (c['type']?.toString() ?? '').replaceFirst(RegExp(r'^custom:'), '');

extension CardOpts on CardConfig {
  double numOr(String key, double d) => (this[key] as num?)?.toDouble() ?? d;

  int intOr(String key, int d) => (this[key] as num?)?.toInt() ?? d;

  bool boolOr(String key, bool d) => this[key] is bool ? this[key] as bool : d;

  String? str(String key) {
    return this[key]?.toString();
  }

  List<dynamic> listOr(String key) =>
      this[key] is List ? this[key] as List : const [];

  List<CardConfig> maps(String key) => listOr(key)
      .map(
        (e) => e is Map
            ? e.cast<String, dynamic>()
            : (e is String ? {'entity': e} : null),
      )
      .whereType<CardConfig>()
      .toList();

  /// `title` wins, `name` is the older spelling, then the entity's own name.
  String titleOr(String fallback) => str('title') ?? str('name') ?? fallback;
}

/// Turn a Lovelace dashboard into pages for the panel.
///
/// The layout the cards' README recommends is one panel view holding a swipe
/// card, whose children (usually vertical-stacks) are the pages. That is what
/// this reads first.
///
/// When a weather card opts into `show_switches`, its embedded light controls
/// are sourced from the nspanel-light-card definitions on the other swipe
/// pages. The original Lights page remains unchanged and renders normally.
List<PanelPage> pagesFromLovelace(Map<String, dynamic> config) {
  final views = (config['views'] as List?) ?? const [];
  final pages = <PanelPage>[];

  for (final view in views) {
    if (view is! Map) {
      continue;
    }

    final cards = _cardsOf(view);

    CardConfig? swipe;

    for (final card in cards) {
      if (cardType(card).endsWith('swipe-card') && card['cards'] is List) {
        swipe = card;
        break;
      }
    }

    if (swipe != null) {
      for (final child in swipe.maps('cards')) {
        pages.add(PanelPage(_flattenPageRoot(child)));
      }
    } else if (cards.isNotEmpty) {
      pages.add(PanelPage(cards.expand(_flattenPageRoot).toList()));
    }
  }

  _attachEmbeddedLights(pages);

  return pages;
}

/// Collect the light-card definitions from the Lights pages and attach them
/// to the opted-in weather card on the first page.
///
/// This is internal panel configuration only; it does not mutate the original
/// dashboard configuration or remove cards from their original page.
void _attachEmbeddedLights(List<PanelPage> pages) {
  if (pages.isEmpty) {
    return;
  }

  // Les pages passées ici sont les pages effectives, après génération
  // conditionnelle et parsing du YAML. Aucune liste d'entités n'est codée
  // en dur dans cette couche.
  final lights = <CardConfig>[];

  for (final page in pages) {
    for (final card in page.cards) {
      _collectLightCards(card, lights);
    }
  }

  if (lights.isEmpty) {
    return;
  }

  // Attache les définitions YAML aux cartes météo qui le demandent,
  // quelle que soit leur position dans les pages générées.
  for (var i = 0; i < pages.length; i++) {
    pages[i] = PanelPage([
      for (final card in pages[i].cards)
        _attachLightsToWeather(card, lights),
    ]);
  }
}

void _collectLightCards(CardConfig card, List<CardConfig> lights) {
  if (cardType(card) == 'nspanel-light-card') {
    lights.add(Map<String, dynamic>.from(card));
    return;
  }

  for (final child in card.maps('cards')) {
    _collectLightCards(child, lights);
  }
}

CardConfig _attachLightsToWeather(
  CardConfig card,
  List<CardConfig> lights,
) {
  final copy = Map<String, dynamic>.from(card);

  if (cardType(copy) == 'nspanel-weather-pro-card' &&
      copy.boolOr('show_switches', false)) {
    copy['_embedded_lights'] = [
      for (final light in lights) Map<String, dynamic>.from(light),
    ];
  }

  final children = copy['cards'];

  if (children is List) {
    copy['cards'] = [
      for (final child in children)
        if (child is Map)
          _attachLightsToWeather(
            child.cast<String, dynamic>(),
            lights,
          )
        else
          child,
    ];
  }

  return copy;
}

/// Read the cards of a Lovelace view.
///
/// Supports both the traditional `cards:` form and the newer sections
/// structure. Ordering is preserved.
List<CardConfig> _cardsOf(Map view) {
  final direct = (view['cards'] as List?) ?? const [];

  if (direct.isNotEmpty) {
    return direct
        .whereType<Map>()
        .map((map) => map.cast<String, dynamic>())
        .toList();
  }

  final sections = (view['sections'] as List?) ?? const [];

  return [
    for (final section in sections.whereType<Map>())
      for (final card
          in (section['cards'] as List? ?? const []).whereType<Map>())
        card.cast<String, dynamic>(),
  ];
}

/// Convert a Lovelace root card into the cards that make up a panel page.
///
/// A top-level vertical-stack is flattened into its direct children.
/// Screensaver cards are configuration, not renderable page cards, so they
/// are removed recursively from the page copy without mutating the source
/// Lovelace configuration.
List<CardConfig> _flattenPageRoot(CardConfig card) {
  final cleaned = _withoutScreensaver(card);
  if (cleaned == null) {
    return const [];
  }

  if (cardType(cleaned) == 'vertical-stack' && cleaned['cards'] is List) {
    return cleaned.maps('cards');
  }

  return [cleaned];
}

/// Return a cleaned copy of a card, or null when it is a screensaver.
///
/// Only the copied page structure is changed; the original configuration
/// remains available to the code that handles screensaver settings.
CardConfig? _withoutScreensaver(CardConfig card) {
  if (cardType(card) == 'nspanel-screensaver') {
    return null;
  }

  final cleaned = Map<String, dynamic>.from(card);
  final children = cleaned['cards'];

  if (children is List) {
    final filtered = <dynamic>[];

    for (final child in children) {
      if (child is! Map) {
        filtered.add(child);
        continue;
      }

      final cleanedChild =
          _withoutScreensaver(Map<String, dynamic>.from(child));

      if (cleanedChild != null) {
        filtered.add(cleanedChild);
      }
    }

    cleaned['cards'] = filtered;
  }

  return cleaned;
}
