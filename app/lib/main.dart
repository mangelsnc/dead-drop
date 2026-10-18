import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sodium_libs/sodium_libs.dart';

import 'ui/home_page.dart';

/// Global sodium instance provider.
final sodiumProvider = Provider<Sodium>((ref) {
  throw UnimplementedError('sodiumProvider must be overridden in main()');
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sodium = await SodiumInit.init();
  runApp(
    ProviderScope(
      overrides: [
        sodiumProvider.overrideWithValue(sodium),
      ],
      child: const DeadDropApp(),
    ),
  );
}

class DeadDropApp extends StatelessWidget {
  const DeadDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeadDrop',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
