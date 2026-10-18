import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sodium_libs/sodium_libs.dart';

import '../src/emitter.dart';
import '../src/crypto.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  Sodium? _sodium;
  Emitter? _emitter;
  Uint8List? _bootstrapQr;
  bool _isReady = false;
  String _status = 'Select a file to send';
  double _fps = 10.0;
  int _chunkSize = 512;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _sodium = await SodiumInit.init();
    setState(() => _isReady = true);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) {
      setState(() => _status = 'Could not read file');
      return;
    }

    setState(() => _status = 'Preparing ${file.name}...');

    // For now, generate a temporary receiver keypair
    // In the real app, the receiver shows their public key as a QR first
    final receiverKp = await ReceiverKeypair.generate(_sodium!);

    _emitter = await Emitter.create(
      _sodium!,
      file.bytes!,
      receiverKp,
      chunkSize: _chunkSize,
    );

    _bootstrapQr = _emitter!.bootstrapQrPayload();
    setState(() => _status = 'Ready: ${file.name} (${file.size} bytes)');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(_status, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _isReady ? _pickFile : null,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Choose file'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_bootstrapQr != null) ...[
              const Text('Bootstrap QR (show to receiver):'),
              const SizedBox(height: 8),
              Center(
                child: QrImageView(
                  data: String.fromCharCodes(_bootstrapQr!),
                  size: 200,
                ),
              ),
              const SizedBox(height: 16),
              const Text('Adjust parameters:'),
              Slider(
                value: _fps,
                min: 1,
                max: 30,
                divisions: 29,
                label: '${_fps.round()} fps',
                onChanged: (v) => setState(() => _fps = v),
              ),
              DropdownButtonFormField<int>(
                value: _chunkSize,
                decoration: const InputDecoration(labelText: 'Chunk size'),
                items: [256, 512, 1024, 2048]
                    .map((s) => DropdownMenuItem(value: s, child: Text('$s bytes')))
                    .toList(),
                onChanged: (v) => setState(() => _chunkSize = v!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
