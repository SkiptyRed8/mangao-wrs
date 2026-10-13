import 'package:flutter/material.dart';

import 'screens/root.dart';
import 'services/nav.dart';
import 'theme/brand.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MangaoApp());
}

class MangaoApp extends StatelessWidget {
  const MangaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mangao WRS',
      debugShowCheckedModeBanner: false,
      navigatorKey: navKey,
      scaffoldMessengerKey: messengerKey,
      theme: buildTheme(),
      // In Chrome on the laptop, show the app at phone size in the middle of the window.
      builder: (context, child) => LayoutBuilder(
        builder: (context, box) => box.maxWidth <= 520
            ? child!
            : ColoredBox(
                color: Brand.light,
                child: Center(
                  child: Container(
                    width: 420,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border.fromBorderSide(BorderSide(color: Brand.blue, width: 1.2)),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 18)],
                    ),
                    child: ClipRect(
                      child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(size: Size(420, box.maxHeight)),
                        child: child!,
                      ),
                    ),
                  ),
                ),
              ),
      ),
      home: const Root(),
    );
  }
}
