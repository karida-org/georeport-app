import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/issues/issue_providers.dart';

/// Bytes of a same-instance asset, fetched with the active connection's
/// credentials (plain `Image.network` cannot carry the bearer token).
///
/// Deliberately NOT kept alive for the session: this is an unbounded family
/// (one entry per attachment URL), and pinning every photo a user scrolled
/// past would grow without limit on a device with little memory. A short
/// grace period keeps scrolling back and forth cheap, and Flutter's own image
/// cache still holds the decoded frames.
final authedImageProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, urlOrPath) {
      final link = ref.keepAlive();
      final timer = Timer(const Duration(minutes: 2), link.close);
      ref.onDispose(timer.cancel);
      return ref.watch(activeClientProvider).fetchBytes(urlOrPath);
    });

class AuthedImage extends ConsumerWidget {
  const AuthedImage({
    required this.urlOrPath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    super.key,
  });

  final String urlOrPath;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(authedImageProvider(urlOrPath));
    return SizedBox(
      width: width,
      height: height,
      child: bytes.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (_, _) => const Center(child: Icon(Icons.broken_image)),
        data: (data) => Image.memory(data, fit: fit),
      ),
    );
  }
}
