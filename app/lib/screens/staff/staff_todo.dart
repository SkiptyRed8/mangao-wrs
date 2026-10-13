import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../shell.dart';
import '../station/log_forms.dart';

/// Staff 1: To Do (filled in by step 30).
class StaffTodo extends StatelessWidget {
  const StaffTodo({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: topBar(context, 'To Do'),
        body: const Body([
          StationButtons(),
          Gap(14),
          ComingSoonCard(step: 30, what: 'Tank counter, Processing list, Mark Out for Delivery'),
        ]),
      );
}
