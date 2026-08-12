import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/net/connectivity.dart';

void main() {
  test('any active interface counts as online', () {
    expect(anyNetwork([ConnectivityResult.wifi]), isTrue);
    expect(
      anyNetwork([ConnectivityResult.mobile, ConnectivityResult.vpn]),
      isTrue,
    );
    expect(anyNetwork([ConnectivityResult.none]), isFalse);
    expect(anyNetwork([]), isFalse);
  });
}
