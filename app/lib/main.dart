import 'package:flutter/material.dart';

void main() {
  runApp(const DeadDropApp());
}

class DeadDropApp extends StatelessWidget {
  const DeadDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeadDrop',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text('DeadDrop — Air-gapped file transfer'),
        ),
      ),
    );
  }
}
