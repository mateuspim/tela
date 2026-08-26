import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/offload_run.dart';
import 'package:tela/app/offload_run_controller.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/byte_size_text.dart';
import 'package:tela/domain/models/offload_group.dart';
import 'package:tela/features/settings/download_location_controller.dart';
import 'package:tela/features/settings/offload_action.dart';
import 'package:tela/features/settings/offload_controller.dart';
import 'package:tela/features/settings/offload_group_text.dart';
import 'package:tela/features/settings/offload_progress_panel.dart';

/// Picks which piles of already-downloaded images move onto the SD card.
///
/// Its own screen rather than a settings tile that just acts, because the
/// decision has three parts the user has to see before committing: what is on
/// the device, what each pile costs to leave there, and what moving it changes
/// besides the location.
class OffloadScreen extends ConsumerWidget {
  /// Creates the offload screen.
  const OffloadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.offloadTitle)),
      body: ref
          .watch(offloadGroupsProvider)
          .when(
            data: (List<OffloadGroup> groups) => _OffloadBody(groups: groups),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object error, StackTrace stack) =>
                _Notice(text: l10n.errorUnexpected),
          ),
    );
  }
}

/// The list, the tally and the button — everything that needs the survey.
class _OffloadBody extends ConsumerWidget {
  const _OffloadBody({required this.groups});

  final List<OffloadGroup> groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final OffloadRun? run = ref.watch(offloadRunProvider);
    // The run outranks the survey. Its figures were taken before the move
    // started, so a list drawn beside a half-finished one would offer ticks
    // over files that are no longer where it says they are.
    if (run != null) return _Running(run: run);
    if (!_cardOnOffer(ref)) return _Notice(text: l10n.offloadNoCard);
    if (groups.isEmpty) return _Notice(text: l10n.offloadNothingToMove);
    return Column(
      children: <Widget>[
        Expanded(child: _list(context, l10n)),
        _OffloadFooter(groups: groups),
      ],
    );
  }

  /// Whether a card is even present. The screen has nothing to offer without
  /// one, and saying so beats a list of ticks whose button cannot run.
  bool _cardOnOffer(WidgetRef ref) {
    return ref.watch(downloadLocationProvider).value?.offersSdCard ?? false;
  }

  Widget _list(BuildContext context, AppLocalizations l10n) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      children: <Widget>[
        Text(l10n.offloadIntro, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        for (final OffloadGroup group in groups) _GroupTile(group: group),
      ],
    );
  }
}

/// One tickable pile: what it is, what it costs, and what moving it changes.
class _GroupTile extends ConsumerWidget {
  const _GroupTile({required this.group});

  final OffloadGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool selected = ref
        .watch(offloadSelectionProvider)
        .contains(group.kind);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: CheckboxListTile(
        key: Key('offload-group-${group.kind.name}'),
        value: selected,
        onChanged: (_) =>
            ref.read(offloadSelectionProvider.notifier).toggle(group.kind),
        isThreeLine: true,
        title: Row(
          children: <Widget>[
            Expanded(child: Text(offloadGroupLabel(l10n, group.kind))),
            Text(
              l10n.offloadFreed(formatBytes(group.bytes)),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        subtitle: Text(offloadGroupDetail(l10n, group.kind, group.count)),
      ),
    );
  }
}

/// The running tally and the one button, pinned under the list.
class _OffloadFooter extends ConsumerWidget {
  const _OffloadFooter({required this.groups});

  final List<OffloadGroup> groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<OffloadGroup> picked = _picked(ref);
    final int count = picked.fold(0, (int n, OffloadGroup g) => n + g.count);
    final int bytes = picked.fold(0, (int n, OffloadGroup g) => n + g.bytes);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                l10n.offloadSelectedTotal(count, formatBytes(bytes)),
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('offload-run'),
                onPressed: picked.isEmpty
                    ? null
                    : () => unawaited(_run(context, ref, picked)),
                icon: const Icon(Icons.sd_card_outlined),
                label: Text(l10n.offloadAction),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<OffloadGroup> _picked(WidgetRef ref) {
    final Set<OffloadKind> selected = ref.watch(offloadSelectionProvider);
    return <OffloadGroup>[
      for (final OffloadGroup group in groups)
        if (selected.contains(group.kind)) group,
    ];
  }

  /// Starts the move and leaves it running. Nothing here awaits the result:
  /// the panel that replaces this footer reads it from [offloadRunProvider].
  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    List<OffloadGroup> picked,
  ) async {
    await runOffload(context: context, ref: ref, groups: picked);
  }
}

/// The screen while a move is running, or reporting the one that just did.
class _Running extends StatelessWidget {
  const _Running({required this.run});

  final OffloadRun run;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      children: <Widget>[OffloadProgressPanel(run: run)],
    );
  }
}

/// A single sentence where the list would be — no card, or nothing to move.
class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
