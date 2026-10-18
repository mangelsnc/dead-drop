import 'package:flutter/material.dart';

import 'send_screen.dart';
import 'receive_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DeadDrop'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.qr_code, size: 80),
            const SizedBox(height: 24),
            const Text(
              'Air-gapped file transfer',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 48),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SendScreen()),
              ),
              icon: const Icon(Icons.upload),
              label: const Text('Send a file'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReceiveScreen()),
              ),
              icon: const Icon(Icons.download),
              label: const Text('Receive a file'),
            ),
          ],
        ),
      ),
    );
  }
}
