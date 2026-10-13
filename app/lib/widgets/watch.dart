import 'package:flutter/widgets.dart';

import '../services/app_state.dart';

/// Rebuilds [builder] whenever the app state changes (log in, log out, view switch, tab).
class Watch extends StatelessWidget {
  final WidgetBuilder builder;
  const Watch(this.builder, {super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: app, builder: (c, _) => builder(c));
}
