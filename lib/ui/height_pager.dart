import 'package:flutter/material.dart';

import '../config/resolution.dart';
import '../cards/env.dart';
import '../cards/registry.dart';
import '../config/dashboard.dart';
import 'motion.dart';
import 'pager.dart';
import 'theme.dart';

/// Splits dashboard components into pages according to their actual geometry.
///
/// Layouts that fit remain intact. Oversized layouts are expanded into their
/// children before pagination so that their contents continue on later pages.
/// A built-in Home Assistant panel always occupies a page of its own.
class HeightPager extends StatelessWidget {
  const HeightPager({
    super.key,
    required this.pages,
    required this.env,
    this.jump,
    this.onPage,
    this.animatePage,
  });

  final List<PanelPage> pages;
  final PanelEnv env;
  final ValueNotifier<int>? jump;
  final ValueChanged<int>? onPage;
  final bool Function(int index)? animatePage;

  List<CardConfig> _flattenCards() => [
        for (final page in pages)
          for (final card in page.cards) card,
      ];

  bool _isBuiltInPanel(CardConfig card) =>
      resolveCard(card, panels: env.panels).kind ==
      ResolvedCardKind.builtInPanel;

  bool _containsBuiltInPanel(CardConfig card) {
    if (_isBuiltInPanel(card)) return true;

    for (final child in card.maps('cards')) {
      if (_containsBuiltInPanel(child)) return true;
    }

    return false;
  }

  double _cardHeight(CardConfig card, double availablePageHeight) {
    if (_isBuiltInPanel(card)) return availablePageHeight;

    switch (cardType(card)) {
      case 'nspanel-light-card':
      case 'nspanel-cover-card':
      case 'nspanel-climate-card':
      case 'nspanel-media-card':
      case 'nspanel-switch-card':
      case 'nspanel-button-card':
      case 'nspanel-alarm-card':
      case 'nspanel-sensor-card':
      case 'nspanel-status-card':
      case 'nspanel-clock-card':
        return card.numOr('height', 200);

      case 'nspanel-weather-card':
        return card.numOr('height', 240);

      case 'nspanel-sensors-card':
        return card.numOr('height', 130);

      case 'nspanel-weather-pro-card':
        final configured = card.numOr('height', 0);
        return configured > 0 ? configured : availablePageHeight;

      case 'nspanel-screensaver':
        return 0;

      case 'vertical-stack':
        final children = card.maps('cards');
        var total = 0.0;

        for (var i = 0; i < children.length; i++) {
          if (i > 0) total += Ns.gap;
          total += _cardHeight(children[i], availablePageHeight);
        }

        return total;

      case 'horizontal-stack':
        final children = card.maps('cards');
        var tallest = 0.0;

        for (final child in children) {
          tallest = tallest.max(_cardHeight(child, availablePageHeight));
        }

        return tallest;

      case 'grid':
        final children = card.maps('cards');
        if (children.isEmpty) return 0;

        final columns = card.intOr('columns', 3).clamp(1, 4);
        var total = 0.0;

        for (var start = 0; start < children.length; start += columns) {
          if (start > 0) total += Ns.gap;

          var rowHeight = 0.0;
          final end = (start + columns).clamp(0, children.length);

          for (var i = start; i < end; i++) {
            rowHeight = rowHeight.max(
              _cardHeight(children[i], availablePageHeight),
            );
          }

          total += rowHeight;
        }

        return total;

      default:
        return card.numOr('height', 200);
    }
  }

  /// Keeps layouts that fit, but expands layouts that overflow or contain a
  /// built-in panel. The resulting cards are then paginated in their original
  /// order. This avoids placing a full-page WebView inside another layout.
  List<CardConfig> _expandForPagination(
    CardConfig card,
    double availableHeight,
  ) {
    final resolved = resolveCard(card, panels: env.panels);

    if (resolved.kind != ResolvedCardKind.layout) {
      return [card];
    }

    final children = card.maps('cards');
    if (children.isEmpty) return [card];

    final hasPanel = _containsBuiltInPanel(card);
    final overflows = _cardHeight(card, availableHeight) >
        availableHeight + 0.5;

    if (!hasPanel && !overflows) {
      return [card];
    }

    // When a horizontal stack or grid cannot fit, its children become
    // sequential pagination units instead of being clipped off-screen.
    return [
      for (final child in children)
        ..._expandForPagination(child, availableHeight),
    ];
  }

  List<PanelPage> _paginate(
    List<CardConfig> cards,
    double availableHeight,
  ) {
    final result = <PanelPage>[];
    var current = <CardConfig>[];
    var used = 0.0;

    void flushCurrent() {
      if (current.isEmpty) return;

      result.add(PanelPage(List<CardConfig>.from(current)));
      current = <CardConfig>[];
      used = 0.0;
    }

    for (final card in cards) {
      final height = _cardHeight(card, availableHeight);
      if (height <= 0) continue;

      // A built-in panel must be alone on its page.
      if (_isBuiltInPanel(card)) {
        flushCurrent();
        result.add(PanelPage([card]));
        continue;
      }

      final gap = current.isEmpty ? 0.0 : Ns.gap;
      final required = gap + height;

      if (current.isNotEmpty &&
          used + required > availableHeight + 0.5) {
        flushCurrent();
      }

      current.add(card);
      used += (current.length == 1 ? 0.0 : Ns.gap) + height;
    }

    flushCurrent();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final outerHeight = constraints.maxHeight;
          if (outerHeight <= 0) return const SizedBox.expand();

          final cards = _flattenCards();
          if (cards.isEmpty) return const SizedBox.expand();

          var availableHeight =
              PanelPager.contentHeight(outerHeight, multiplePages: true);

          var preparedCards = [
            for (final card in cards)
              ..._expandForPagination(card, availableHeight),
          ];

          var splitPages = _paginate(preparedCards, availableHeight);

          // If only one page is needed, reclaim the space reserved for
          // page indicators and calculate the layout again.
          if (splitPages.length == 1) {
            availableHeight =
                PanelPager.contentHeight(outerHeight, multiplePages: false);

            preparedCards = [
              for (final card in cards)
                ..._expandForPagination(card, availableHeight),
            ];

            splitPages = _paginate(preparedCards, availableHeight);
          }

          if (splitPages.isEmpty) return const SizedBox.expand();

          final deferredPages = <int>{
            for (var i = 0; i < splitPages.length; i++)
              if (splitPages[i].cards.any(_containsBuiltInPanel)) i,
          };

          return PanelPager(
            jump: jump,
            onPage: onPage,
            deferredPages: deferredPages,
            pages: [
              for (var i = 0; i < splitPages.length; i++)
                _buildPage(
                  splitPages[i],
                  pageIndex: i,
                  animate: animatePage?.call(i) ?? false,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPage(
    PanelPage page, {
    required int pageIndex,
    required bool animate,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < page.cards.length; i++) ...[
          if (i > 0) const SizedBox(height: Ns.gap),
          _buildCard(
            page.cards[i],
            pageIndex: pageIndex,
            cardIndex: i,
            animate: animate,
          ),
        ],
      ],
    );
  }

  Widget _buildCard(
    CardConfig card, {
    required int pageIndex,
    required int cardIndex,
    required bool animate,
  }) {
    return KeyedSubtree(
      key: ValueKey(
        'dashboard-card-${pageIndex}_$cardIndex-${cardType(card)}',
      ),
      child: Enter(
        index: cardIndex,
        animate: animate,
        child: buildCard(card, env),
      ),
    );
  }
}

extension on double {
  double max(double other) => this > other ? this : other;
}
