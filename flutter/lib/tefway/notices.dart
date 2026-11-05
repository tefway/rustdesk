// The Client's diagnostics adapter.
//
// Every value comes from the running machine: the platform, the core's error
// string and the display-server questions the core already answers. The pure
// model lives in `diagnostics_model.dart`, so the list can be tested without a
// core or a window. The cards the old Client rendered directly on the home
// surface are now reachable through the header's Central de Diagnósticos, and
// only a blocking core error stays in the affected flow.

import 'package:flutter/material.dart';

import '../common.dart';
import '../models/platform_model.dart';
import 'design.dart';
import 'diagnostics_model.dart';
import 'strings.dart';

/// Reads this machine and returns its diagnostics.
List<TefwayDiagnostic> tefwayDiagnostics({
  String coreError = '',
  VoidCallback? onRetryCore,
}) {
  var waylandSession = false;
  var loginWayland = false;
  var selinuxEnforcing = false;
  if (isLinux) {
    waylandSession = bind.mainCurrentIsWayland();
    if (!waylandSession) loginWayland = bind.mainIsLoginWayland();
    selinuxEnforcing = bind.isSelinuxEnforcing();
  }
  return buildTefwayDiagnostics(
    windows: isWindows,
    linux: isLinux,
    waylandSession: waylandSession,
    loginWayland: loginWayland,
    selinuxEnforcing: selinuxEnforcing,
    coreError: coreError.isEmpty ? '' : translate(coreError),
    onRetryCore: onRetryCore,
  );
}

/// A real connection error reported by the core, kept in the affected flow as
/// well as in the diagnostics panel: a blocking error must not be reachable
/// only through an icon.
class TefwayCoreErrorNotice extends StatelessWidget {
  const TefwayCoreErrorNotice({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return TefwayNoticeCard(
      status: TefwayDiagnosticSeverity.critical,
      title: TefwayStrings.errorTitle,
      message: translate(message),
      consequence: TefwayStrings.diagnosticsCoreConsequence,
      actionLabel: onRetry == null ? null : TefwayStrings.retry,
      onAction: onRetry,
    );
  }
}

/// Inline card for the affected flow. The panel reuses the same fields.
class TefwayNoticeCard extends StatelessWidget {
  const TefwayNoticeCard({
    super.key,
    required this.status,
    required this.title,
    required this.message,
    required this.consequence,
    this.actionLabel,
    this.onAction,
  });

  final TefwayDiagnosticSeverity status;
  final String title;
  final String message;
  final String consequence;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      TefwayDiagnosticSeverity.info => TefwayColors.textSecondary,
      TefwayDiagnosticSeverity.warning => TefwayColors.attention,
      TefwayDiagnosticSeverity.critical => TefwayColors.critical,
    };
    final icon = switch (status) {
      TefwayDiagnosticSeverity.info => Icons.info_outline_rounded,
      TefwayDiagnosticSeverity.warning => Icons.warning_amber_rounded,
      TefwayDiagnosticSeverity.critical => Icons.error_outline_rounded,
    };
    return Container(
      padding: const EdgeInsets.all(TefwaySpacing.md),
      decoration: BoxDecoration(
        color: TefwayColors.inputFill,
        borderRadius: TefwayRadius.mdAll,
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: TefwaySpacing.sm),
              Expanded(
                child: Text(title, style: TefwayTextStyles.sectionTitle),
              ),
            ],
          ),
          const SizedBox(height: TefwaySpacing.xs),
          Text(message, style: TefwayTextStyles.body),
          const SizedBox(height: TefwaySpacing.xs),
          Text(consequence, style: TefwayTextStyles.caption),
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: TefwaySpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: TefwayColors.actionBlue,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
