/// known_senders_page.dart — the people this device has received from.
///
/// A sender's fingerprint is stable: IdentityStore keeps one Ed25519
/// identity per device, so the same person shows the same code on every
/// transfer. That is what makes naming them worth doing — "From Ana" is
/// something a human can check against their own memory, where sixteen
/// hex characters are not.
///
/// A name is a **local label, not an authenticated claim**. It is what
/// this user typed on this device; it says "this is the key I decided was
/// Ana's", never "this key belongs to Ana". The page says so rather than
/// letting a name read as proof.
///
/// The list is scoped to the open vault environment, like the store
/// behind it. The decoy must not show the real environment's contacts —
/// a list of real people inside the decoy is exactly the tell the vault
/// exists to avoid.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart';
import '../technical_text.dart';
import '../theme.dart';

class KnownSendersPage extends ConsumerStatefulWidget {
  const KnownSendersPage({super.key});

  @override
  ConsumerState<KnownSendersPage> createState() => _KnownSendersPageState();
}

class _KnownSendersPageState extends ConsumerState<KnownSendersPage> {
  late Future<Map<String, String?>> _senders;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _senders = ref.read(tofuStoreProvider).all();
  }

  Future<void> _rename(String fingerprint, String? current) async {
    final controller = TextEditingController(text: current ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(current == null ? 'Name this sender' : 'Rename'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(fingerprint, style: technicalTextStyle(ref)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Ana',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.of(context).pop(v),
            ),
            const SizedBox(height: 12),
            Text(
              'A label for you, on this device. It is not proof of who '
              'they are.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: DeadDropColors.textSecondary,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null) return;

    await ref.read(tofuStoreProvider).setName(fingerprint, name);
    if (mounted) setState(_reload);
  }

  Future<void> _forget(String fingerprint, String? name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Forget ${name ?? 'this sender'}?'),
        content: const Text(
          'The next transfer from them will ask you to check their code '
          'again, as if you had never received from them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(tofuStoreProvider).forget(fingerprint);
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Known senders')),
      body: SafeArea(
        child: FutureBuilder<Map<String, String?>>(
          future: _senders,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final senders = snapshot.data!;
            if (senders.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.people_outline,
                          size: 48, color: DeadDropColors.textSecondary),
                      const SizedBox(height: 16),
                      Text(
                        'Nobody yet. A sender appears here once you have '
                        'checked their code and accepted a transfer.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: DeadDropColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              itemCount: senders.length + 1,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i == senders.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Names are labels you chose, stored on this device. '
                      'They are not proof of identity — the code beneath '
                      'each one is what actually identifies a sender.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: DeadDropColors.textSecondary,
                          ),
                    ),
                  );
                }

                final fingerprint = senders.keys.elementAt(i);
                final name = senders[fingerprint];

                return ListTile(
                  leading: Icon(
                    name == null ? Icons.person_outline : Icons.person,
                    color: name == null
                        ? DeadDropColors.textSecondary
                        : DeadDropColors.success,
                  ),
                  title: Text(
                    name ?? 'Unnamed sender',
                    style: name == null
                        ? const TextStyle(color: DeadDropColors.textSecondary)
                        : null,
                  ),
                  subtitle: Text(fingerprint, style: technicalTextStyle(ref)),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) => action == 'rename'
                        ? _rename(fingerprint, name)
                        : _forget(fingerprint, name),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'rename',
                        child: Text(name == null ? 'Name' : 'Rename'),
                      ),
                      const PopupMenuItem(
                        value: 'forget',
                        child: Text('Forget'),
                      ),
                    ],
                  ),
                  onTap: () => _rename(fingerprint, name),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
