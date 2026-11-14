import 'package:flutter/widgets.dart';

/// Clears text-field focus when a route is dismissed.
///
/// Android restores the previously focused field when a dialog or page is
/// popped, which can bounce the keyboard back up after the user closed it.
/// Dropping focus on pop keeps the keyboard down.
class UnfocusRouteObserver extends NavigatorObserver {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    FocusManager.instance.primaryFocus?.unfocus();
  }
}
