import 'package:flutter/material.dart';

import 'theme.dart';

/// Pages side by side, swiped.
///
/// Pages containing a native Home Assistant panel are deferred until active.
/// A deferred page is mounted only after the page transition has finished.
/// The previous WebView is unmounted before the next one is created.
class PanelPager extends StatefulWidget {
  const PanelPager({
    super.key,
    required this.pages,
    this.jump,
    this.onPage,
    this.deferredPages = const <int>{},
  });

  final List<Widget> pages;

  /// Page indices whose contents must only be mounted while active.
  ///
  /// Used for pages containing WebViews. This prevents neighboring pages from
  /// initializing native WebView resources during PageView preloading.
  final Set<int> deferredPages;

  /// Set a page index here and the pager goes there - how HA turns the page.
  final ValueNotifier<int>? jump;
  final ValueChanged<int>? onPage;

  static EdgeInsets pagePadding({required bool multiplePages}) {
    return const EdgeInsets.fromLTRB(Ns.gap, Ns.gap, Ns.gap, 0);
  }

  static double contentWidth(double outerWidth) {
    return (outerWidth - (Ns.gap * 2)).clamp(0.0, double.infinity);
  }

  static double contentHeight(
    double outerHeight, {
    required bool multiplePages,
  }) {
    final padding = pagePadding(multiplePages: multiplePages);

    return (outerHeight - padding.top - padding.bottom).clamp(
      0.0,
      double.infinity,
    );
  }

  @override
  State<PanelPager> createState() => _PanelPagerState();
}

class _PanelPagerState extends State<PanelPager> {
  int _index = 0;

  /// Index of the deferred page whose contents may currently be mounted.
  ///
  /// This is deliberately independent from [_index]: onPageChanged fires
  /// before the page transition has necessarily finished.
  int? _activeDeferredIndex = 0;

  /// Invalidates pending post-frame activations after a newer page transition.
  int _activationGeneration = 0;

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
      _activationGeneration++;
      if (_index != 0 || _activeDeferredIndex != null) {
        setState(() {
          _index = 0;
          _activeDeferredIndex = null;
        });
      }
      return;
    }

    final last = widget.pages.length - 1;

    if (_index > last) {
      _activationGeneration++;
      setState(() {
        _index = last;
        _activeDeferredIndex = null;
      });

      if (_controller.hasClients) {
        _controller.jumpToPage(last);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) {
          return;
        }
        _settlePage();
      });
      return;
    }

    // Keep the active deferred page consistent if the page configuration
    // changes while the current page remains the same.
    if (oldWidget.deferredPages != widget.deferredPages &&
        !widget.deferredPages.contains(_index) &&
        _activeDeferredIndex != null) {
      _activationGeneration++;
      setState(() => _activeDeferredIndex = null);
    }
  }

  @override
  void dispose() {
    _activationGeneration++;
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

  void _onPageChanged(int index) {
    if (!mounted) {
      return;
    }

    setState(() => _index = index);
    widget.onPage?.call(index);
  }

  /// Called when PageView scrolling has actually ended.
  ///
  /// First unmount the previous deferred page. A post-frame callback then
  /// mounts the destination page, so the old and new WebViews are not
  /// intentionally kept alive together during a page transition.
  void _settlePage() {
    if (!mounted || widget.pages.isEmpty || !_controller.hasClients) {
      return;
    }

    final page = _controller.page;
    final target = (page ?? _index.toDouble()).round().clamp(
      0,
      widget.pages.length - 1,
    );

    final targetIsDeferred = widget.deferredPages.contains(target);

    if (_activeDeferredIndex == target && targetIsDeferred) {
      return;
    }

    final generation = ++_activationGeneration;

    if (_activeDeferredIndex != null) {
      setState(() => _activeDeferredIndex = null);
    }

    if (!targetIsDeferred) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _activationGeneration ||
          !_controller.hasClients) {
        return;
      }

      // A new swipe may have started since this callback was scheduled.
      if (_controller.position.isScrollingNotifier.value) {
        return;
      }

      final currentPage = (_controller.page ?? _index.toDouble()).round().clamp(
        0,
        widget.pages.length - 1,
      );

      if (currentPage != target || !widget.deferredPages.contains(target)) {
        return;
      }

      setState(() => _activeDeferredIndex = target);
    });
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
        NotificationListener<ScrollEndNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) {
              _settlePage();
            }
            return false;
          },
          child: PageView.builder(
            controller: _controller,

            // Native-only dashboards retain implicit scrolling. Dashboards
            // with deferred WebViews must not preload neighboring pages.
            allowImplicitScrolling: widget.deferredPages.isEmpty,
            itemCount: widget.pages.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (_, i) {
              final deferredAndInactive =
                  widget.deferredPages.contains(i) && _activeDeferredIndex != i;

              return SizedBox.expand(
                child: Padding(
                  padding: padding,
                  child: deferredAndInactive
                      ? const SizedBox.expand()
                      : widget.pages[i],
                ),
              );
            },
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
