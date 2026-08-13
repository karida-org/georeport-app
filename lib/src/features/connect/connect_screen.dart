import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../api/base_url.dart';
import '../../api/models/capabilities.dart';
import '../../auth/oauth_config.dart';
import '../../auth/oauth_flow.dart';
import '../../connections/connection_manager.dart';
import 'saved_connections_list.dart';

/// Onboarding and instance switching: probe an instance from its URL, then
/// sign in with the browser (when the instance advertises a mobile OAuth
/// application) or with a pasted API key. Saved instances are offered first.
class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  // Bounds on a whole step, not on one request. Dio already times out each
  // call; these exist because a step can also stall outside the network, in
  // platform secure storage, which blocks indefinitely on a device with a
  // broken keystore.
  //
  // Each is set above what the step can legitimately take, because failing a
  // working connection is worse than waiting. What they rule out is waiting
  // for ever.

  /// One request.
  static const probeTimeout = Duration(seconds: 60);

  /// Up to five requests (capabilities, credential check, settings, user,
  /// bundle) at up to 30s of receive time each, plus the secret write.
  static const apiKeyConnectTimeout = Duration(minutes: 3);

  /// The browser sign-in waits on a person, and [OAuthFlow.browserTimeout]
  /// already bounds that with a message about sign-in specifically. This is
  /// only a backstop for a stall elsewhere in the step, so it must stay above
  /// that inner bound and should never be the one to fire.
  static const oauthConnectTimeout = Duration(minutes: 10);

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

  /// Runs a connect step with the busy flag, a bound, and a readable failure.
  ///
  /// [failureMessage] turns whatever went wrong into what the user reads.
  Future<void> _run(
    Future<void> Function() action, {
    required String Function(Object error) failureMessage,
    required String timeoutMessage,
    required Duration timeout,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action().timeout(
        timeout,
        onTimeout: () => throw TimeoutException(timeoutMessage),
      );
    } on TimeoutException catch (timeout) {
      if (mounted) {
        setState(() => _error = timeout.message ?? timeoutMessage);
      }
      // Catch everything: a malformed probe response surfaces as a TypeError
      // (an Error, not an Exception), and a silent no-op would strand the
      // user on an idle-looking screen.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      if (mounted) {
        setState(() => _error = failureMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Rejects an address that cannot be a URL before any request is made, so a
  /// typo reads as an instruction rather than as a parser diagnostic.
  bool _rejectUnusableUrl(AppLocalizations l10n) {
    if (isUsableBaseUrl(_urlController.text)) {
      return false;
    }
    setState(() => _error = l10n.connectInvalidUrl);
    return true;
  }

  Future<void> _probe(AppLocalizations l10n) async {
    if (_rejectUnusableUrl(l10n)) {
      return;
    }
    await _run(
      () async {
        final capabilities = await ref
            .read(connectionManagerProvider.notifier)
            .probe(normalizeBaseUrl(_urlController.text));
        setState(() => _probed = capabilities);
      },
      failureMessage: (error) => l10n.connectFailed('$error'),
      timeoutMessage: l10n.connectTimedOut,
      timeout: ConnectScreen.probeTimeout,
    );
  }

  Future<void> _signInWithOAuth(AppLocalizations l10n) async {
    if (_rejectUnusableUrl(l10n)) {
      return;
    }
    await _run(
      () async {
        await ref
            .read(connectionManagerProvider.notifier)
            .connectWithOAuth(
              baseUrl: normalizeBaseUrl(_urlController.text),
              capabilities: _probed!,
            );
      },
      failureMessage: (error) => l10n.connectFailed('$error'),
      timeoutMessage: l10n.connectTimedOut,
      timeout: ConnectScreen.oauthConnectTimeout,
    );
  }

  Future<void> _connectWithApiKey(AppLocalizations l10n) async {
    if (_rejectUnusableUrl(l10n)) {
      return;
    }
    await _run(
      () async {
        await ref
            .read(connectionManagerProvider.notifier)
            .connectWithApiKey(
              baseUrl: normalizeBaseUrl(_urlController.text),
              apiKey: _apiKeyController.text.trim(),
            );
      },
      failureMessage: (error) => l10n.connectFailed('$error'),
      timeoutMessage: l10n.connectTimedOut,
      timeout: ConnectScreen.apiKeyConnectTimeout,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // All navigation into the app is state-driven: whenever a connection
    // becomes active (startup reconnect, sign-in, or switching), leave for
    // the issues screen.
    ref.listen(connectionManagerProvider, (previous, next) {
      if (next.value?.active != null && mounted) {
        context.go('/home');
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
                // The brand mark picks its variant by theme; clearspace
                // (one dot-diameter around the mark) comes from the padding.
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: SvgPicture.asset(
                    Theme.of(context).brightness == Brightness.dark
                        ? 'assets/brand/georeport-mark-dark.svg'
                        : 'assets/brand/georeport-mark.svg',
                    height: 72,
                  ),
                ),
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
                    _error!,
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
          onSubmitted: (_) {
            if (!_busy && _urlController.text.trim().isNotEmpty) {
              _probe(l10n);
            }
          },
        ),
        const SizedBox(height: 16),
        if (probed == null)
          FilledButton(
            onPressed: _busy || _urlController.text.trim().isEmpty
                ? null
                : () => _probe(l10n),
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
              onPressed: _busy ? null : () => _signInWithOAuth(l10n),
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
              onPressed: _busy ? null : () => _connectWithApiKey(l10n),
              child: Text(l10n.connectButton),
            ),
          ],
        ],
      ],
    );
  }
}
