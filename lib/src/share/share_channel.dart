import 'dart:async';

import 'package:flutter/services.dart';

/// Thin wrapper over the `georeport/share` platform channel. Android copies
/// images shared from other apps into the cache directory and hands their
/// file paths over here; iOS has no share extension yet and simply never
/// emits anything.
class ShareChannel {
  ShareChannel([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('georeport/share');

  final MethodChannel _channel;
  final _shares = StreamController<List<String>>.broadcast();

  /// Batches of shared image file paths, one event per share action.
  Stream<List<String>> get shares => _shares.stream;

  /// Starts listening for pushed shares and drains anything that arrived
  /// before Dart was ready (a share that cold-started the app).
  Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared') {
        _shares.add(List<String>.from(call.arguments as List));
      }
    });
    try {
      final initial = await _channel.invokeListMethod<String>(
        'getInitialShare',
      );
      if (initial != null && initial.isNotEmpty) {
        _shares.add(initial);
      }
    } on MissingPluginException {
      // No native handler on this platform; nothing to drain.
    }
  }
}
