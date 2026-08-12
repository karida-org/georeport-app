import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/connections/connection.dart';
import 'package:georeport/src/connections/connection_store.dart';

import '../helpers/in_memory_secret_store.dart';

void main() {
  late InMemorySecretStore secrets;
  late ConnectionStore store;

  setUp(() {
    secrets = InMemorySecretStore();
    store = ConnectionStore(secrets);
  });

  test('round-trips connections and the active selection', () async {
    const connection = Connection(
      id: '1',
      label: 'demo',
      baseUrl: 'https://demo.example.org',
      authKind: ConnectionAuthKind.oauth,
    );
    await store.saveConnections(const [connection]);
    await store.saveActiveId('1');

    final loaded = await store.loadConnections();
    expect(loaded, hasLength(1));
    expect(loaded.single.label, 'demo');
    expect(loaded.single.authKind, ConnectionAuthKind.oauth);
    expect(await store.loadActiveId(), '1');

    await store.saveActiveId(null);
    expect(await store.loadActiveId(), isNull);
  });

  test('secrets are stored per connection and deletable', () async {
    await store.writeSecret('1', {'kind': 'api_key', 'api_key': 'k'});
    expect((await store.readSecret('1'))?['api_key'], 'k');

    await store.deleteSecret('1');
    expect(await store.readSecret('1'), isNull);
    expect(
      secrets.values.keys.where((k) => k.contains('secret')),
      isEmpty,
      reason: 'no secret material may remain after deletion',
    );
  });

  test('tolerates corrupt stored payloads', () async {
    secrets.values['georeport.connections'] = '{"not": "a list"}';
    expect(await store.loadConnections(), isEmpty);

    secrets.values['georeport.connections'] = '{';
    expect(await store.loadConnections(), isEmpty);

    secrets.values['georeport.secret.1'] = '{';
    expect(await store.readSecret('1'), isNull);
  });
}
