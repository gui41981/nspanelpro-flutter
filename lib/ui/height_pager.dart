import 'package:flutter/material.dart';

import '../cards/env.dart';
import '../cards/registry.dart';
import '../config/dashboard.dart';
import 'motion.dart';
import 'pager.dart';
import 'theme.dart';

/// Splits dashboard components into pages according to their actual card
/// geometry.
///
/// There is deliberately no device/model/card-count logic here.
///
/// Cards already expose their root height in their implementation:
///   - most cards: 200
///   - weather: 240
///   - sensors: 130
///   - weather-pro: configured height, or one full page
///
/// Layout cards are resolved recursively:
///   - vertical-stack  -> sum of children + gaps
///   - horizontal-stack -> tallest child
///   - grid             -> tallest child in each row + row gaps
///
/// The important part is that cards are NOT rendered once for measurement and
/// a second time for the real pager. They are built only in the real pager,
/// preserving their normal Flutter layout/state.
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

  List<CardConfig> _flattenCards() {
    return [
      for (final page in pages)
        for (final card in page.cards) card,
    ];
  }

  double _cardHeight(CardConfig card, double availablePageHeight) {
    final type = cardType(card);

    switch (type) {
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
        if (children.isEmpty) {
          return 0;
        }

        var total = 0.0;

        for (var i = 0; i < children.length; i++) {
          if (i > 0) {
            total += Ns.gap;
          }

          total += _cardHeight(children[i], availablePageHeight);
        }

        return total;

      case 'horizontal-stack':
        final children = card.maps('cards');
        if (children.isEmpty) {
          return 0;
        }

        var tallest = 0.0;

        for (final child in children) {
          tallest = tallest.max(_cardHeight(child, availablePageHeight));
        }

        return tallest;

      case 'grid':
        final children = card.maps('cards');
        if (children.isEmpty) {
          return 0;
        }

        final columns = card.intOr('columns', 3).clamp(1, 4);

        var total = 0.0;

        for (var start = 0; start < children.length; start += columns) {
          if (start > 0) {
            total += Ns.gap;
          }

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
        // Unknown/built-in cards keep a sensible normal card footprint.
        return card.numOr('height', 200);
    }
  }

  List<PanelPage> _paginate(List<CardConfig> cards, double availableHeight) {
    final result = <PanelPage>[];
    var current = <CardConfig>[];
    var used = 0.0;

    for (final card in cards) {
      final height = _cardHeight(card, availableHeight);

      if (height <= 0) {
        continue;
      }

      final gap = current.isEmpty ? 0.0 : Ns.gap;
      final required = gap + height;

      if (current.isNotEmpty && used + required > availableHeight + 0.5) {
        result.add(PanelPage(List<CardConfig>.from(current)));

        current = <CardConfig>[];
        used = 0.0;
      }

      current.add(card);
      used += (current.length == 1 ? 0.0 : Ns.gap) + height;
    }

    if (current.isNotEmpty) {
      result.add(PanelPage(List<CardConfig>.from(current)));
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final outerHeight = constraints.maxHeight;

          if (outerHeight <= 0) {
            return const SizedBox.expand();
          }

          final cards = _flattenCards();

          if (cards.isEmpty) {
            return const SizedBox.expand();
          }

          // First paginate with the space reserved for page indicators.
          // If everything fits on one page, reclaim that space.
          var splitPages = _paginate(
            cards,
            PanelPager.contentHeight(outerHeight, multiplePages: true),
          );

          if (splitPages.length == 1) {
            splitPages = _paginate(
              cards,
              PanelPager.contentHeight(outerHeight, multiplePages: false),
            );
          }

          if (splitPages.isEmpty) {
            return const SizedBox.expand();
          }

          return PanelPager(
            jump: jump,
            onPage: onPage,
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
      key: ValueKey('dashboard-card-${pageIndex}_$cardIndex-${cardType(card)}'),
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
