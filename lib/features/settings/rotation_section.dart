import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tela/app/providers.dart';
import 'package:tela/core/i18n/generated/app_localizations.dart';
import 'package:tela/domain/models/rotation_plan.dart';
import 'package:tela/domain/models/wallpaper_target.dart';
import 'package:tela/domain/ports/wallpaper_rotation.dart';

/// The auto-rotate schedule the platform is currently running, or null.
///
/// Read from the scheduler rather than from tela's own settings, so the switch
/// cannot claim a schedule the platform does not have — a restored backup or a
/// cleared database would otherwise leave the two disagreeing.
final AsyncNotifierProvider<RotationController, RotationPlan?>
rotationProvider = AsyncNotifierProvider<RotationController, RotationPlan?>(
  RotationController.new,
);

/// Starts, stops and reshapes the schedule.
class RotationController extends AsyncNotifier<RotationPlan?> {
  @override
  Future<RotationPlan?> build() {
    return ref.watch(wallpaperRotationProvider).current();
  }

  /// Rotates on [plan] from now on, replacing any existing schedule.
  Future<void> start(RotationPlan plan) async {
    final WallpaperRotation rotation = ref.read(wallpaperRotationProvider);
    await rotation.start(plan);
    state = AsyncData<RotationPlan?>(plan);
  }

  /// Stops rotating.
  Future<void> stop() async {
    await ref.read(wallpaperRotationProvider).stop();
    state = const AsyncData<RotationPlan?>(null);
  }

  /// Changes one part of a running schedule, re-enqueueing it.
  ///
  /// Re-enqueueing rather than editing, because the platform has no notion of
  /// editing periodic work — and starting from [RotationPlan.defaults] when
  /// nothing is running is what lets a picker be used before the switch.
  Future<void> reshape(RotationPlan Function(RotationPlan current) change) {
    return start(change(state.value ?? RotationPlan.defaults));
  }
}

/// The auto-rotate rows: the switch, and the three choices behind it.
class RotationSection extends ConsumerWidget {
  /// Creates the auto-rotate section of the settings screen.
  const RotationSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final RotationPlan? plan = ref.watch(rotationProvider).value;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SwitchListTile(
          secondary: const Icon(Icons.schedule_outlined),
          title: Text(l10n.rotationTitle),
          subtitle: Text(
            plan == null ? l10n.rotationOff : _summary(l10n, plan),
          ),
          value: plan != null,
          onChanged: (bool on) => unawaited(_toggle(ref, on: on)),
        ),
        // The pickers only exist while something is scheduled: choosing an
        // interval for a rotation that is off would be configuring nothing.
        if (plan != null) ..._choices(context, ref, l10n, plan),
      ],
    );
  }

  Future<void> _toggle(WidgetRef ref, {required bool on}) {
    final RotationController controller = ref.read(rotationProvider.notifier);
    return on ? controller.start(RotationPlan.defaults) : controller.stop();
  }

  List<Widget> _choices(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    RotationPlan plan,
  ) {
    return <Widget>[
      ListTile(
        title: Text(l10n.rotationInterval),
        trailing: DropdownButton<RotationInterval>(
          value: plan.interval,
          onChanged: (RotationInterval? picked) => unawaited(
            _reshape(ref, (RotationPlan p) => p.copyWith(interval: picked)),
          ),
          items: <DropdownMenuItem<RotationInterval>>[
            for (final RotationInterval each in RotationInterval.values)
              DropdownMenuItem<RotationInterval>(
                value: each,
                child: Text(_intervalLabel(l10n, each)),
              ),
          ],
        ),
      ),
      ListTile(
        title: Text(l10n.rotationSource),
        trailing: DropdownButton<RotationSource>(
          value: plan.source,
          onChanged: (RotationSource? picked) => unawaited(
            _reshape(ref, (RotationPlan p) => p.copyWith(source: picked)),
          ),
          items: <DropdownMenuItem<RotationSource>>[
            for (final RotationSource each in RotationSource.values)
              DropdownMenuItem<RotationSource>(
                value: each,
                child: Text(_sourceLabel(l10n, each)),
              ),
          ],
        ),
      ),
      // Said plainly, because "Private library" does not say it: a rotation
      // puts its pick where anyone glancing at the phone sees it.
      if (plan.source == RotationSource.privateLibrary)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            l10n.rotationPrivateWarning,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      ListTile(
        title: Text(l10n.rotationTarget),
        trailing: DropdownButton<WallpaperTarget>(
          value: plan.target,
          onChanged: (WallpaperTarget? picked) => unawaited(
            _reshape(ref, (RotationPlan p) => p.copyWith(target: picked)),
          ),
          items: <DropdownMenuItem<WallpaperTarget>>[
            for (final WallpaperTarget each in WallpaperTarget.values)
              DropdownMenuItem<WallpaperTarget>(
                value: each,
                child: Text(_targetLabel(l10n, each)),
              ),
          ],
        ),
      ),
    ];
  }

  Future<void> _reshape(
    WidgetRef ref,
    RotationPlan Function(RotationPlan plan) change,
  ) {
    return ref.read(rotationProvider.notifier).reshape(change);
  }

  /// All three choices in one line, so the switch says what it is doing.
  String _summary(AppLocalizations l10n, RotationPlan plan) {
    return l10n.rotationSummary(
      _intervalLabel(l10n, plan.interval),
      _sourceLabel(l10n, plan.source),
      _targetLabel(l10n, plan.target),
    );
  }

  static String _intervalLabel(
    AppLocalizations l10n,
    RotationInterval interval,
  ) => switch (interval) {
    RotationInterval.quarterHour => l10n.rotationIntervalQuarterHour,
    RotationInterval.hourly => l10n.rotationIntervalHourly,
    RotationInterval.sixHourly => l10n.rotationIntervalSixHourly,
    RotationInterval.daily => l10n.rotationIntervalDaily,
  };

  static String _sourceLabel(AppLocalizations l10n, RotationSource source) =>
      switch (source) {
        RotationSource.gallery => l10n.rotationSourceGallery,
        RotationSource.filesOutsideGallery => l10n.rotationSourceFiles,
        RotationSource.privateLibrary => l10n.rotationSourcePrivate,
      };

  /// Reuses the apply sheet's own words rather than a second set that could
  /// drift from them — a wallpaper surface is a wallpaper surface.
  static String _targetLabel(AppLocalizations l10n, WallpaperTarget target) =>
      switch (target) {
        WallpaperTarget.home => l10n.detailTargetHome,
        WallpaperTarget.lock => l10n.detailTargetLock,
        WallpaperTarget.both => l10n.detailTargetBoth,
      };
}
