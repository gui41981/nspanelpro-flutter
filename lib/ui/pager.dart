import 'package:flutter/material.dart';

import 'theme.dart';

/// Pages side by side, swiped.
///
/// HeightPager uses the geometry exposed here to decide how many cards fit.
/// The page indicators are an overlay and therefore do not consume vertical
/// space from the dashboard itself.
class PanelPager extends StatefulWidget {
  const PanelPager({
    super.key,
    required this.pages,
    this.jump,
    this.onPage,
  });

  final List<Widget> pages;

  /// Set a page index here and the pager goes there - how HA turns the page.
  final ValueNotifier<int>? jump;
  final ValueChanged<int>? onPage;

  /// Padding around the actual dashboard content.
  ///
  /// The page indicators are painted above the PageView and do not reduce the
  /// available dashboard height.
  static EdgeInsets pagePadding({
    required bool multiplePages,
  }) {
    return const EdgeInsets.fromLTRB(
      Ns.gap,
      Ns.gap,
      Ns.gap,
      0,
    );
  }

  /// Width available to the actual dashboard content.
  static double contentWidth(double outerWidth) {
    return (
      outerWidth -
      (Ns.gap * 2)
    ).clamp(0.0, double.infinity);
  }

  /// Height available to the actual dashboard content.
  ///
  /// Only the top page margin is removed. The indicator is an overlay and
  /// therefore does not consume dashboard height.
  static double contentHeight(
    double outerHeight, {
    required bool multiplePages,
  }) {
    final padding = pagePadding(multiplePages: multiplePages);

    return (
      outerHeight -
      padding.top -
      padding.bottom
    ).clamp(0.0, double.infinity);
  }

  @override
  State<PanelPager> createState() => _PanelPagerState();
}

class _PanelPagerState extends State<PanelPager> {
  int _index = 0;
  final _controller = PageController();

  @override
  void initState() {
    super.initState();
    widget.jump?.addListener(_onJump);
  }

  @override
  void didUpdateWidget(covariant PanelPager oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.jump, widget.jump)) {
      oldWidget.jump?.removeListener(_onJump);
      widget.jump?.addListener(_onJump);
    }

    if (widget.pages.isEmpty) {
      if (_index != 0) {
        setState(() => _index = 0);
      }
      return;
    }

    final last = widget.pages.length - 1;

    if (_index > last) {
      setState(() => _index = last);

      if (_controller.hasClients) {
        _controller.jumpToPage(last);
      }
    }
  }

  @override
  void dispose() {
    widget.jump?.removeListener(_onJump);
    _controller.dispose();
    super.dispose();
  }

  void _onJump() {
    if (widget.pages.isEmpty) {
      return;
    }

    final i = widget.jump!.value.clamp(0, widget.pages.length - 1);

    if (!_controller.hasClients || i == _index) {
      return;
    }

    _controller.animateToPage(
      i,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) {
      return const SizedBox.expand();
    }

    final many = widget.pages.length > 1;
    final padding = PanelPager.pagePadding(multiplePages: many);

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          allowImplicitScrolling: true,
          itemCount: widget.pages.length,
          onPageChanged: (i) {
            setState(() => _index = i);
            widget.onPage?.call(i);
          },
          itemBuilder: (_, i) => SizedBox.expand(
            child: Padding(
              padding: padding,
              child: widget.pages[i],
            ),
          ),
        ),
        if (many)
          Positioned(
            left: 0,
            right: 0,
            bottom: 7,
            child: IgnorePointer(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < widget.pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 3.5),
                      width: i == _index ? 8 : 7,
                      height: i == _index ? 8 : 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _index
                            ? Ns.text
                            : Colors.white.withValues(alpha: .22),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
