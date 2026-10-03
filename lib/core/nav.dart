import 'package:flutter/widgets.dart';

/// Switches the signed-in bottom bar. Screens call this instead of pushing
/// a second copy of Transport or Staff.
class LgNav extends InheritedWidget {
  const LgNav({required this.go, required super.child, super.key});

  final void Function(String tabKey) go;

  static LgNav? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LgNav>();

  @override
  bool updateShouldNotify(LgNav oldWidget) => go != oldWidget.go;
}
