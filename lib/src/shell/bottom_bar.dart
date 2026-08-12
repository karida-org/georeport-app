import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';

/// The five-slot bottom bar: Issues, Map, a raised Home button in the
/// center, Capture, and Time. Home, Issues, Map, and Time are stateful
/// shell branches; Capture pushes its flow on the root navigator, so it
/// never shows as selected.
class GeoreportBottomBar extends StatelessWidget {
  const GeoreportBottomBar({required this.shell, super.key});

  final StatefulNavigationShell shell;

  /// Branch indices in router order (see router.dart).
  static const _home = 0;
  static const _issues = 1;
  static const _map = 2;
  static const _time = 3;

  void _goBranch(int branch) => shell.goBranch(
    branch,
    // Re-tapping the active destination pops its branch to the root,
    // the platform-conventional "go home" gesture.
    initialLocation: branch == shell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              _BarItem(
                icon: Icons.checklist_outlined,
                selectedIcon: Icons.checklist,
                label: l10n.navIssues,
                selected: shell.currentIndex == _issues,
                onTap: () => _goBranch(_issues),
              ),
              _BarItem(
                icon: Icons.map_outlined,
                selectedIcon: Icons.map,
                label: l10n.issuesMapTab,
                selected: shell.currentIndex == _map,
                onTap: () => _goBranch(_map),
              ),
              _HomeButton(
                selected: shell.currentIndex == _home,
                onTap: () => _goBranch(_home),
              ),
              _BarItem(
                icon: Icons.add_a_photo_outlined,
                selectedIcon: Icons.add_a_photo,
                label: l10n.navCapture,
                selected: false,
                onTap: () => context.push('/capture'),
              ),
              _BarItem(
                icon: Icons.timer_outlined,
                selectedIcon: Icons.timer,
                label: l10n.navTime,
                selected: shell.currentIndex == _time,
                onTap: () => _goBranch(_time),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? selectedIcon : icon, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// The emphasized center slot: for a field worker the anchor is "my day",
/// so Home takes the raised button (not compose, as report-first apps do).
class _HomeButton extends StatelessWidget {
  const _HomeButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Center(
        child: Tooltip(
          message: l10n.navHome,
          child: Material(
            color: scheme.primary,
            shape: const CircleBorder(),
            elevation: selected ? 1 : 4,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 56,
                height: 56,
                child: Icon(
                  selected ? Icons.home : Icons.home_outlined,
                  color: scheme.onPrimary,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
