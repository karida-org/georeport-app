import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'connection_provider.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      await ref
          .read(connectionProvider.notifier)
          .connect(
            baseUrl: _urlController.text,
            apiKey: _apiKeyController.text,
          );
      if (mounted) {
        context.go('/issues');
      }
    } on Exception catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
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
                  TextFormField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      labelText: l10n.connectInstanceUrlLabel,
                      hintText: 'https://redmine.example.org',
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? l10n.connectFieldRequired
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _apiKeyController,
                    decoration: InputDecoration(
                      labelText: l10n.connectApiKeyLabel,
                      border: const OutlineInputBorder(),
                    ),
                    obscureText: true,
                    autocorrect: false,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? l10n.connectFieldRequired
                        : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _connecting ? null : _connect,
                    child: _connecting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.connectButton),
                  ),
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
      ),
    );
  }
}
