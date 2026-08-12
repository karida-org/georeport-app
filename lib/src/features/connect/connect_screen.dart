import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../api/base_url.dart';
import '../../api/models/capabilities.dart';
import '../../auth/oauth_config.dart';
import '../../connections/connection_manager.dart';
import 'saved_connections_list.dart';

/// Onboarding and instance switching: probe an instance from its URL, then
/// sign in with the browser (when the instance advertises a mobile OAuth
/// application) or with a pasted API key. Saved instances are offered first.
class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  Capabilities? _probed;
  bool _busy = false;
  bool _showApiKey = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      // Catch everything: a malformed probe response surfaces as a TypeError
      // (an Error, not an Exception), and a silent no-op would strand the
      // user on an idle-looking screen.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _probe() => _run(() async {
    final capabilities = await ref
        .read(connectionManagerProvider.notifier)
        .probe(normalizeBaseUrl(_urlController.text));
    setState(() => _probed = capabilities);
  });

  Future<void> _signInWithOAuth() => _run(() async {
    await ref
        .read(connectionManagerProvider.notifier)
        .connectWithOAuth(
          baseUrl: normalizeBaseUrl(_urlController.text),
          capabilities: _probed!,
        );
  });

  Future<void> _connectWithApiKey() => _run(() async {
    await ref
        .read(connectionManagerProvider.notifier)
        .connectWithApiKey(
          baseUrl: normalizeBaseUrl(_urlController.text),
          apiKey: _apiKeyController.text.trim(),
        );
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // All navigation into the app is state-driven: whenever a connection
    // becomes active (startup reconnect, sign-in, or switching), leave for
    // the issues screen.
    ref.listen(connectionManagerProvider, (previous, next) {
      if (next.value?.active != null && mounted) {
        context.go('/issues');
      }
    });
    final manager = ref.watch(connectionManagerProvider);
    final connections = manager.value?.connections ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.homeTagline,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                if (manager.isLoading && connections.isEmpty)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  if (connections.isNotEmpty) ...[
                    Text(
                      l10n.connectSavedInstances,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    SavedConnectionsList(connections: connections),
                    const SizedBox(height: 24),
                    Text(
                      l10n.connectAddInstance,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                  ],
                  _buildInstanceForm(l10n),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    l10n.connectFailed(_error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInstanceForm(AppLocalizations l10n) {
    final probed = _probed;
    final oauthAvailable =
        probed != null &&
        oauthConfigFor(normalizeBaseUrl(_urlController.text), probed) != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _urlController,
          decoration: InputDecoration(
            labelText: l10n.connectInstanceUrlLabel,
            hintText: 'https://redmine.example.org',
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
          autocorrect: false,
          enabled: !_busy,
          // Rebuild on every edit: the Continue button's enabled state
          // follows the field, and an URL change invalidates a prior probe.
          onChanged: (_) => setState(() => _probed = null),
          onSubmitted: (_) => _probe(),
        ),
        const SizedBox(height: 16),
        if (probed == null)
          FilledButton(
            onPressed: _busy || _urlController.text.trim().isEmpty
                ? null
                : _probe,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.connectContinueButton),
          )
        else ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.dns),
              title: Text(
                Uri.parse(normalizeBaseUrl(_urlController.text)).host,
              ),
              subtitle: Text(l10n.connectServerSummary(probed.redmineVersion)),
            ),
          ),
          const SizedBox(height: 8),
          if (oauthAvailable) ...[
            FilledButton.icon(
              onPressed: _busy ? null : _signInWithOAuth,
              icon: const Icon(Icons.open_in_browser),
              label: Text(l10n.connectSignInButton),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _showApiKey = !_showApiKey),
              child: Text(l10n.connectUseApiKeyInstead),
            ),
          ],
          if (!oauthAvailable || _showApiKey) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _apiKeyController,
              decoration: InputDecoration(
                labelText: l10n.connectApiKeyLabel,
                border: const OutlineInputBorder(),
              ),
              obscureText: true,
              autocorrect: false,
              enabled: !_busy,
            ),
            const SizedBox(height: 8),
            (oauthAvailable ? OutlinedButton.new : FilledButton.new)(
              onPressed: _busy ? null : _connectWithApiKey,
              child: Text(l10n.connectButton),
            ),
          ],
        ],
      ],
    );
  }
}
