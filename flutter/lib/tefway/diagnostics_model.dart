// Pure diagnostics model for the Tefway Client.
//
// Deliberately free of platform or FFI imports so it can be unit-tested on the
// VM. `notices.dart` is the adapter that reads the running machine and hands
// the values to `buildTefwayDiagnostics`.
//
// A condition the operating system reports is not, by itself, a failure:
// Wayland being active does not mean capture is broken, and SELinux enforcing
// does not mean it is blocking. Those stay `info`; only a condition the core
// actually reported (a real error) is `critical`, and only that kind can be
// marked as blocking.

import 'package:flutter/foundation.dart';

import 'strings.dart';

enum TefwayDiagnosticSeverity { info, warning, critical }

/// One diagnostic entry. [id] is stable and unique: two producers reporting
/// the same condition collapse into one entry.
class TefwayDiagnostic {
  const TefwayDiagnostic({
    required this.id,
    required this.severity,
    required this.title,
    required this.message,
    required this.consequence,
    this.details,
    this.action,
    this.actionLabel,
    this.onAction,
    this.blocksSession = false,
  });

  final String id;
  final TefwayDiagnosticSeverity severity;
  final String title;
  final String message;

  /// What this means for a support session, in the customer's terms.
  final String consequence;

  /// Technical explanation, shown only when the operator expands it.
  final String? details;

  /// Recommended action. Only present when there is something real to do.
  final String? action;

  /// A safe action that can actually run (for example, retry the core read).
  final String? actionLabel;
  final VoidCallback? onAction;

  /// True only for a condition the core reported and that prevents a session.
  final bool blocksSession;
}

/// Builds the current list, de-duplicated by id, keeping the first (and
/// therefore most specific) producer of each condition.
List<TefwayDiagnostic> buildTefwayDiagnostics({
  required bool windows,
  required bool linux,
  required bool waylandSession,
  required bool loginWayland,
  required bool selinuxEnforcing,
  String coreError = '',
  VoidCallback? onRetryCore,
}) {
  final byId = <String, TefwayDiagnostic>{};

  void add(TefwayDiagnostic diagnostic) {
    byId.putIfAbsent(diagnostic.id, () => diagnostic);
  }

  if (coreError.isNotEmpty) {
    add(TefwayDiagnostic(
      id: 'core-error',
      severity: TefwayDiagnosticSeverity.critical,
      title: TefwayStrings.errorTitle,
      message: coreError,
      consequence: TefwayStrings.diagnosticsCoreConsequence,
      action: TefwayStrings.diagnosticsCoreAction,
      actionLabel: onRetryCore == null ? null : TefwayStrings.retry,
      onAction: onRetryCore,
      blocksSession: true,
    ));
  }

  if (windows) {
    add(const TefwayDiagnostic(
      id: 'windows-uac',
      severity: TefwayDiagnosticSeverity.info,
      title: TefwayStrings.uacTitle,
      message: TefwayStrings.uacBody,
      consequence: TefwayStrings.uacConsequence,
      details: TefwayStrings.uacDetails,
      action: TefwayStrings.uacAction,
    ));
  }

  if (linux) {
    if (waylandSession) {
      add(const TefwayDiagnostic(
        id: 'linux-wayland',
        severity: TefwayDiagnosticSeverity.info,
        title: TefwayStrings.waylandTitle,
        message: TefwayStrings.waylandBody,
        consequence: TefwayStrings.waylandConsequence,
        details: TefwayStrings.waylandDetails,
        action: TefwayStrings.waylandAction,
      ));
    } else if (loginWayland) {
      add(const TefwayDiagnostic(
        id: 'linux-login-wayland',
        severity: TefwayDiagnosticSeverity.warning,
        title: TefwayStrings.loginWaylandTitle,
        message: TefwayStrings.loginWaylandBody,
        consequence: TefwayStrings.loginWaylandConsequence,
        action: TefwayStrings.loginWaylandAction,
      ));
    }
    if (selinuxEnforcing) {
      add(const TefwayDiagnostic(
        id: 'linux-selinux',
        severity: TefwayDiagnosticSeverity.info,
        title: TefwayStrings.selinuxTitle,
        message: TefwayStrings.selinuxBody,
        consequence: TefwayStrings.selinuxConsequence,
        details: TefwayStrings.selinuxDetails,
        action: TefwayStrings.selinuxAction,
      ));
    }
  }

  final list = byId.values.toList()
    ..sort((a, b) => b.severity.index.compareTo(a.severity.index));
  return list;
}

/// Highest severity present, or null when there is nothing to report.
TefwayDiagnosticSeverity? worstSeverity(List<TefwayDiagnostic> diagnostics) {
  TefwayDiagnosticSeverity? worst;
  for (final diagnostic in diagnostics) {
    if (worst == null || diagnostic.severity.index > worst.index) {
      worst = diagnostic.severity;
    }
  }
  return worst;
}
