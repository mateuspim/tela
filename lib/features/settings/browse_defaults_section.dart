import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/account_defaults.dart';
import 'package:tela/app/browse_defaults.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/browse_filter_text.dart';
import 'package:tela/core/ui/wallpaper_failure_text.dart';
import 'package:tela/core/ui/wallpaper_taxonomy_text.dart';
import 'package:tela/domain/models/account_settings.dart';
import 'package:tela/domain/models/browse_defaults.dart';
import 'package:tela/domain/models/category.dart';
import 'package:tela/domain/models/ratio_choice.dart';
import 'package:tela/domain/models/search_query.dart';
import 'package:tela/domain/models/wallhaven_failure.dart';
import 'package:tela/features/settings/api_key_controller.dart';

/// Chooses where browse takes its opening filters from.
///
/// The account option needs a key — without one there is no account to read, so
/// it is offered but disabled rather than hidden: "why can't I pick this" has a
/// better answer than a missing row.
///
/// ```dart
/// const BrowseDefaultsSection()
/// ```
class BrowseDefaultsSection extends ConsumerWidget {
  /// Creates the section.
  const BrowseDefaultsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ActiveBrowseDefaults> active = ref.watch(
      browseDefaultsProvider,
    );
    return active.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const SizedBox.shrink(),
      data: (ActiveBrowseDefaults value) => _Choices(active: value),
    );
  }
}

class _Choices extends ConsumerWidget {
  const _Choices({required this.active});

  final ActiveBrowseDefaults active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool hasKey = ref.watch(apiKeyProvider).value ?? false;
    // Each row describes *its own* source, never the one in force. Otherwise
    // the account's line reads back the device's filters whenever the device is
    // selected — and this is the line you consult before switching.
    final AccountSettings? account = ref.watch(accountDefaultsProvider).value;
    final BrowseDefaults? device = ref.watch(deviceDefaultsProvider).value;
    return RadioGroup<BrowseDefaultsSource>(
      groupValue: active.source,
      onChanged: (BrowseDefaultsSource? source) => _use(ref, source),
      child: Column(
        children: <Widget>[
          RadioListTile<BrowseDefaultsSource>(
            value: BrowseDefaultsSource.account,
            // No key, no account to read. The option stays visible but cannot
            // be picked: "why is this greyed out" has a better answer than a
            // row that is simply missing.
            enabled: hasKey,
            title: Text(l10n.browseDefaultsAccount),
            subtitle: Text(
              _accountSubtitle(context, l10n, account, hasKey: hasKey),
            ),
            secondary: hasKey ? const _RefreshButton() : null,
          ),
          RadioListTile<BrowseDefaultsSource>(
            value: BrowseDefaultsSource.device,
            title: Text(l10n.browseDefaultsDevice),
            subtitle: Text(
              device == null
                  ? l10n.browseDefaultsDeviceHint
                  : _summary(context, device),
            ),
          ),
        ],
      ),
    );
  }

  void _use(WidgetRef ref, BrowseDefaultsSource? source) {
    if (source == null) return;
    unawaited(ref.read(browseDefaultsProvider.notifier).useSource(source));
  }

  String _accountSubtitle(
    BuildContext context,
    AppLocalizations l10n,
    AccountSettings? account, {
    required bool hasKey,
  }) {
    if (!hasKey) return l10n.browseDefaultsNeedsKey;
    if (account == null) return l10n.browseDefaultsNotSynced;
    return _summary(context, account.toBrowseDefaults());
  }

  /// One source's filters, as one line: "General, Anime · Last month ·
  /// Portrait".
  ///
  /// No purity, because neither source carries one — see [BrowseDefaults].
  String _summary(BuildContext context, BrowseDefaults defaults) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String categories = defaults.categories.categories
        .map((Category category) => categoryLabel(l10n, category))
        .join(', ');
    final SearchQuery shaped = defaults.applyTo(const SearchQuery());
    return <String>[
      categories,
      topRangeLabel(l10n, defaults.topRange),
      ratioLabel(l10n, RatioChoice.of(shaped)),
    ].join(' · ');
  }
}

/// Re-pulls the account's settings, for when they changed on the web.
///
/// On demand rather than on a timer: an account's defaults change about as
/// often as its password, and a poll would spend the 45 req/min budget on a
/// question nobody asked.
class _RefreshButton extends ConsumerStatefulWidget {
  const _RefreshButton();

  @override
  ConsumerState<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends ConsumerState<_RefreshButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (_busy) {
      return const SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: l10n.browseDefaultsRefresh,
      onPressed: _refresh,
    );
  }

  /// A failed refresh keeps the defaults it already had. Being offline says
  /// nothing about an account, exactly as it says nothing about a key.
  Future<void> _refresh() async {
    setState(() => _busy = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    String message = l10n.browseDefaultsRefreshed;
    try {
      await ref.read(browseDefaultsProvider.notifier).refreshFromAccount();
    } on WallhavenFailure catch (failure) {
      message = localizedFailure(l10n, failure);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
