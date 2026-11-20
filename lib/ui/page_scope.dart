import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Visibility and screensaver state for a physical dashboard page.
class PageScope extends InheritedWidget {
  const PageScope({
    super.key,
    required this.index,
    required this.shown,
    required this.awake,
    required super.child,
  });

  final int index;
  final ValueListenable<int> shown;
  final ValueListenable<bool> awake;

  bool get active => index >= 0 && shown.value == index && awake.value;

  Listenable get changes => Listenable.merge([shown, awake]);

  static PageScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PageScope>();

  @override
  bool updateShouldNotify(PageScope old) =>
      index != old.index || shown != old.shown || awake != old.awake;
}
