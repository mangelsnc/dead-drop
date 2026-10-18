import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sodium_libs/sodium_libs.dart';

import '../src/crypto.dart';
import '../src/receiver.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  Sodium? _sodium;
  ReceiverKeypair? _keypair;
  Receiver? _receiver;
  bool _isReady = false;
  String _status = 'Initializing...';
  double _progress = 0.0;
  int _framesReceived = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _sodium = await SodiumInit.init();
    _keypair = await ReceiverKeypair.generate(_sodium!);
    _receiver = Receiver(sodium: _sodium!, keypair: _keypair!);
    setState(() {
      _isReady = true;
      _status = 'Point camera at sender screen';
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_isReady || _receiver == null) return;

    for (final barcode in capture.barcodes) {
      if (barcode.rawBytes == null) continue;

      try {
        final advanced = _receiver!.feedFrame(barcode.rawBytes!);
        if (advanced) {
          setState(() {
            _framesReceived++;
            _progress = _receiver!.progress;
            _status = 'Receiving... ${(_progress * 100).toStringAsFixed(1)}%';
          });

          if (_receiver!.done) {
            final plaintext = _receiver!.finish();
            setState(() {
              _status = 'Done! Received ${plaintext.length} bytes';
            });
            // TODO: Save file with file_picker
          }
        }
      } catch (e) {
        // Frame dropped (bad QR, wrong session, etc.)
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receive')),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: MobileScanner(
              onDetect: _onDetect,
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_status, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 8),
                  Text('Frames received: $_framesReceived'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
