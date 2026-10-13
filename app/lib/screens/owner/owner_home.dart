import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../shell.dart';
import '../station/log_forms.dart';

/// Admin Home 1 (filled in by step 27).
class OwnerHome extends StatelessWidget {
  const OwnerHome({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: topBar(context, 'Home'),
        body: const Body([
          StationButtons(),
          Gap(14),
          ComingSoonCard(step: 27, what: "Switch View, tank counter, Needs Your Action, Today's Summary, stock alerts"),
        ]),
      );
}
