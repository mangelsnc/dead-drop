/// technical_text.dart — one place that decides how fingerprints, keys and
/// passphrases are drawn.
///
/// These strings are read character by character: a fingerprint is
/// compared against one on someone else's screen, a public key is typed or
/// checked, a passphrase is copied down. The size they are drawn at is
/// therefore a usability property with a security consequence — a
/// comparison nobody can see properly is a control that does not work.
///
/// Before this, seven places each hard-coded their own size. They are all
/// routed through [technicalTextStyle] now, so the setting in Settings
/// reaches every one of them and a new one cannot quietly miss out.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/text_scale.dart';
import 'theme.dart';

/// The user's chosen size for technical text.
///
/// Overridden in `main()` with the stored value so the first frame is
/// already correct — reading it asynchronously would show the default and
/// then jump.
final technicalTextSizeProvider =
    StateProvider<double>((ref) => kDefaultTechnicalTextSize);

/// Persists changes to [technicalTextSizeProvider].
final textScaleStoreProvider = Provider<TextScaleStore>((ref) {
  throw UnimplementedError('textScaleStoreProvider must be overridden');
});

/// The style for a string the user has to read or compare.
///
/// [relativeTo] scales against the user's chosen size rather than
/// replacing it: a heading-sized fingerprint stays proportionally larger
/// when they make everything bigger. Default 1.0 is body size.
TextStyle technicalTextStyle(
  WidgetRef ref, {
  double relativeTo = 1.0,
  Color? color,
  double? letterSpacing,
  FontWeight? fontWeight,
}) {
  final size = ref.watch(technicalTextSizeProvider);
  return TextStyle(
    fontFamily: 'monospace',
    fontSize: size * relativeTo,
    color: color ?? DeadDropColors.textPrimary,
    letterSpacing: letterSpacing,
    fontWeight: fontWeight,
  );
}

/// Larger / smaller buttons with a live sample, for Settings.
///
/// The sample is a real fingerprint rather than the word "Sample": the
/// decision being made is "can I read this when it matters", and only the
/// actual shape of the text answers that.
class TechnicalTextSizeControl extends ConsumerWidget {
  const TechnicalTextSizeControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = ref.watch(technicalTextSizeProvider);

    Future<void> set(double next) async {
      if (next == size) return;
      ref.read(technicalTextSizeProvider.notifier).state = next;
      await ref.read(textScaleStoreProvider).write(next);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Size of codes and keys',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Fingerprints, public keys and passphrases. Larger text '
                    'is easier to compare against another screen.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: DeadDropColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed:
                  size > kMinTechnicalTextSize ? () => set(nextSmaller(size)) : null,
              icon: const Icon(Icons.text_decrease),
              tooltip: 'Smaller',
            ),
            IconButton(
              onPressed:
                  size < kMaxTechnicalTextSize ? () => set(nextLarger(size)) : null,
              icon: const Icon(Icons.text_increase),
              tooltip: 'Larger',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: DeadDropColors.bgElevated,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            'a1b2c3d4e5f6a7b8',
            style: technicalTextStyle(ref, letterSpacing: 2),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
