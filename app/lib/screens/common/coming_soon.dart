import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../shell.dart';

/// Stand-in for a screen that is built in a later step of the tracker.
class ComingSoon extends StatelessWidget {
  final String title;
  final int step;
  final String what;
  final bool pushed;
  const ComingSoon(this.title, {super.key, required this.step, required this.what, this.pushed = false});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: topBar(context, title, back: pushed),
        body: Body([ComingSoonCard(step: step, what: what)]),
      );
}
