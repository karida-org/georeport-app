import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/issues/issue_providers.dart';

/// Bytes of a same-instance asset, fetched with the active connection's
/// credentials (plain `Image.network` cannot carry the bearer token).
/// keepAlive caches the bytes for the session.
final authedImageProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, urlOrPath) {
      ref.keepAlive();
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
