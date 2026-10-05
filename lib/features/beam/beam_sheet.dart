import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/core/ui/beam_failure_text.dart';
import 'package:tela/domain/models/beam_failure.dart';
import 'package:tela/domain/models/beam_file.dart';
import 'package:tela/domain/models/beam_target.dart';
import 'package:tela/features/beam/beam_address_dialog.dart';

/// Picks a machine and sends [files] to it.
///
/// One sheet for the whole flow — discover, choose, send, report — because the
/// three are one decision from the user's side and a screen per step would
/// make a two-tap action feel like a wizard.
///
/// Discovery runs only while this is open: the subscription holds the
/// multicast lock (see `BeamWallpapers.discover`), so closing the sheet is
/// what stops paying for it.
class BeamSheet extends ConsumerStatefulWidget {
  /// Creates the sheet over the files to send.
  const BeamSheet({required this.files, super.key});

  /// What to send. Already resolved to local paths by the caller — a vault
  /// image's SAF URI cannot be read here.
  final List<BeamFile> files;

  /// Opens the sheet, returning once it closes.
  static Future<void> open(
    BuildContext context, {
    required List<BeamFile> files,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      // Root, so the scrim also dims the shell's rail — from a tab's own
      // navigator it stopped at the rail's edge (device survey, 2026-10-05).
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) => BeamSheet(files: files),
    );
  }

  @override
  ConsumerState<BeamSheet> createState() => _BeamSheetState();
}

class _BeamSheetState extends ConsumerState<BeamSheet> {
  final List<BeamTarget> _found = <BeamTarget>[];
  StreamSubscription<BeamTarget>? _discovery;

  /// The target currently being sent to, or null while choosing.
  BeamTarget? _sendingTo;

  /// Bytes acknowledged so far, for the progress bar.
  int _sentBytes = 0;

  /// How long discovery has been quiet, so the empty state can stop claiming
  /// to still be looking.
  bool _searchedLongEnough = false;

  int get _totalBytes => widget.files.fold<int>(
    0,
    (int total, BeamFile file) => total + file.sizeBytes,
  );

  /// The countdown to the empty state, cancelled when discovery restarts.
  Timer? _quietTimer;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  /// Starts (or restarts) discovery from nothing.
  ///
  /// Restartable because a receiver is usually switched on *after* the sheet is
  /// already open — you tap beam, then go and open LocalSend — and without this
  /// the only way to look again was to close the sheet and reopen it. The
  /// announcement is a one-shot shout at the multicast group, so a receiver
  /// that started listening after it went out never hears anything to answer:
  /// re-announcing is the entire point, not just a UI reset.
  void _listen() {
    unawaited(_discovery?.cancel());
    _quietTimer?.cancel();
    setState(() {
      _found.clear();
      _searchedLongEnough = false;
    });
    _discovery = ref
        .read(beamWallpapersProvider)
        .discover()
        .listen(_onFound, onError: (_) {});
    // Discovery never "completes" — receivers appear as they are switched on —
    // so the empty state is timed rather than waiting for a stream to end.
    _quietTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _searchedLongEnough = true);
    });
  }

  void _onFound(BeamTarget target) {
    if (!mounted) return;
    setState(() => _found.add(target));
  }

  @override
  void dispose() {
    // Cancelling is what gives the multicast lock back; leaving it costs
    // battery for the life of the app.
    unawaited(_discovery?.cancel());
    _quietTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              l10n.beamTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (_sendingTo case final BeamTarget target)
              _Progress(
                alias: target.alias,
                sent: _sentBytes,
                total: _totalBytes,
              )
            else
              ..._chooser(l10n),
          ],
        ),
      ),
    );
  }

  List<Widget> _chooser(AppLocalizations l10n) {
    return <Widget>[
      for (final BeamTarget target in _found)
        ListTile(
          leading: Icon(_iconFor(target.kind)),
          title: Text(target.alias),
          subtitle: Text(target.host),
          onTap: () => unawaited(_send(target)),
        ),
      if (_found.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: <Widget>[
              if (!_searchedLongEnough) const CircularProgressIndicator(),
              if (!_searchedLongEnough) const SizedBox(height: 16),
              Text(
                _searchedLongEnough ? l10n.beamNoneFound : l10n.beamSearching,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.center,
        children: <Widget>[
          // Offered once the search has gone quiet, which is the moment it is
          // worth pressing: before that it would just restart a search that is
          // already running.
          if (_searchedLongEnough)
            TextButton.icon(
              icon: const Icon(Icons.refresh),
              label: Text(l10n.beamSearchAgain),
              onPressed: _listen,
            ),
          // Always offered, not only after discovery gives up: a network with
          // client isolation or multicast filtering never answers, and waiting
          // out the timer to be told so is time spent for nothing.
          TextButton.icon(
            icon: const Icon(Icons.keyboard_outlined),
            label: Text(l10n.beamEnterAddress),
            onPressed: () => unawaited(_enterAddress()),
          ),
        ],
      ),
    ];
  }

  static IconData _iconFor(BeamDeviceKind kind) => switch (kind) {
    BeamDeviceKind.desktop => Icons.desktop_windows_outlined,
    BeamDeviceKind.mobile => Icons.smartphone_outlined,
    BeamDeviceKind.web => Icons.public,
    BeamDeviceKind.server || BeamDeviceKind.headless => Icons.dns_outlined,
    BeamDeviceKind.unknown => Icons.devices_other_outlined,
  };

  Future<void> _enterAddress() async {
    final ({String host, int port})? typed =
        await showDialog<
          ({
            String host,
            int port,
          })
        >(
          context: context,
          builder: (BuildContext context) => const BeamAddressDialog(),
        );
    if (typed == null || !mounted) return;
    try {
      final BeamTarget target = await ref
          .read(beamWallpapersProvider)
          .targetAt(host: typed.host, port: typed.port);
      await _send(target);
    } on BeamFailure catch (failure) {
      _report(failure, alias: typed.host);
    }
  }

  Future<void> _send(BeamTarget target) async {
    setState(() {
      _sendingTo = target;
      _sentBytes = 0;
    });
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(beamWallpapersProvider)
          .call(
            target: target,
            files: widget.files,
            onProgress: (int sent) {
              if (mounted) setState(() => _sentBytes = sent);
            },
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      _announce(l10n.beamSent(widget.files.length, target.alias));
    } on BeamFailure catch (failure) {
      if (!mounted) return;
      setState(() => _sendingTo = null);
      _report(failure, alias: target.alias);
    }
  }

  void _report(BeamFailure failure, {required String alias}) {
    _announce(
      localizedBeamFailure(
        AppLocalizations.of(context),
        failure,
        alias: alias,
      ),
    );
  }

  void _announce(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// What is happening while bytes are in flight.
class _Progress extends StatelessWidget {
  const _Progress({
    required this.alias,
    required this.sent,
    required this.total,
  });

  final String alias;
  final int sent;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: <Widget>[
          Text(alias, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            // Indeterminate until the first file lands: progress is reported
            // per completed file, so a zero here means "started", not "stuck".
            value: total == 0 ? null : sent / total,
          ),
        ],
      ),
    );
  }
}
