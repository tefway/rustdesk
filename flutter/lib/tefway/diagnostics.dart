// Central de Diagnósticos: header indicator, count and expandable panel.
//
// The panel reports conditions; it never dismisses, silences or downgrades a
// security check. A blocking error is also rendered in the affected flow by
// `TefwayCoreErrorNotice`, because an error that prevents attendance must not
// be reachable only through an icon.

import 'package:flutter/material.dart';

import 'design.dart';
import 'diagnostics_model.dart';
import 'strings.dart';
import 'widgets.dart';

/// Header indicator. Neutral when there is nothing to report, amber for a
/// warning and red as soon as one entry is critical. The count is always
/// derived from the list, never stored.
class TefwayDiagnosticsButton extends StatelessWidget {
  const TefwayDiagnosticsButton({
    super.key,
    required this.diagnostics,
  });

  final List<TefwayDiagnostic> diagnostics;

  Color get _color {
    switch (worstSeverity(diagnostics)) {
      case TefwayDiagnosticSeverity.critical:
        return TefwayColors.critical;
      case TefwayDiagnosticSeverity.warning:
        return TefwayColors.attention;
      case TefwayDiagnosticSeverity.info:
      case null:
        return TefwayColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = diagnostics.length;
    final label = count == 0
        ? TefwayStrings.diagnosticsOpen
        : TefwayStrings.diagnosticsCount(count);
    return Semantics(
      button: true,
      label: '${TefwayStrings.diagnosticsTitle}: $label',
      child: Tooltip(
        message: label,
        child: Badge.count(
          count: count,
          isLabelVisible: count > 0,
          backgroundColor: _color,
          textColor: TefwayColors.deepNavy,
          child: IconButton(
            onPressed: () => showTefwayDiagnostics(context, diagnostics),
            icon: Icon(Icons.warning_amber_rounded, size: 20, color: _color),
            visualDensity: VisualDensity.compact,
            tooltip: label,
          ),
        ),
      ),
    );
  }
}

Future<void> showTefwayDiagnostics(
  BuildContext context,
  List<TefwayDiagnostic> diagnostics,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(TefwaySpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: TefwaySurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, diagnostics.length),
              const Divider(height: 1, color: TefwayColors.border),
              if (diagnostics.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(TefwaySpacing.xl),
                  child: _EmptyDiagnostics(),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(TefwaySpacing.md),
                    itemCount: diagnostics.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: TefwaySpacing.sm),
                    itemBuilder: (context, index) =>
                        _DiagnosticTile(diagnostic: diagnostics[index]),
                  ),
                ),
              const Divider(height: 1, color: TefwayColors.border),
              Padding(
                padding: const EdgeInsets.all(TefwaySpacing.md),
                child: Text(
                  TefwayStrings.diagnosticsSecurityNote,
                  style: TefwayTextStyles.caption,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _header(BuildContext context, int count) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(
      TefwaySpacing.lg,
      TefwaySpacing.md,
      TefwaySpacing.sm,
      TefwaySpacing.md,
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(TefwayStrings.diagnosticsTitle,
                  style: TefwayTextStyles.sectionTitle),
              const SizedBox(height: 2),
              Text(
                count == 0
                    ? TefwayStrings.diagnosticsNone
                    : TefwayStrings.diagnosticsCount(count),
                style: TefwayTextStyles.caption,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, size: 18),
          color: TefwayColors.textSecondary,
          tooltip: TefwayStrings.diagnosticsClose,
          visualDensity: VisualDensity.compact,
        ),
      ],
    ),
  );
}

class _EmptyDiagnostics extends StatelessWidget {
  const _EmptyDiagnostics();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle_outline_rounded,
            size: 18, color: TefwayColors.positive),
        const SizedBox(width: TefwaySpacing.sm),
        Expanded(
          child: Text(
            TefwayStrings.diagnosticsEmpty,
            style: TefwayTextStyles.bodySecondary,
          ),
        ),
      ],
    );
  }
}

class _DiagnosticTile extends StatefulWidget {
  const _DiagnosticTile({required this.diagnostic});

  final TefwayDiagnostic diagnostic;

  @override
  State<_DiagnosticTile> createState() => _DiagnosticTileState();
}

class _DiagnosticTileState extends State<_DiagnosticTile> {
  bool _expanded = false;

  Color get _color {
    switch (widget.diagnostic.severity) {
      case TefwayDiagnosticSeverity.info:
        return TefwayColors.textSecondary;
      case TefwayDiagnosticSeverity.warning:
        return TefwayColors.attention;
      case TefwayDiagnosticSeverity.critical:
        return TefwayColors.critical;
    }
  }

  IconData get _icon {
    switch (widget.diagnostic.severity) {
      case TefwayDiagnosticSeverity.info:
        return Icons.info_outline_rounded;
      case TefwayDiagnosticSeverity.warning:
        return Icons.warning_amber_rounded;
      case TefwayDiagnosticSeverity.critical:
        return Icons.error_outline_rounded;
    }
  }

  String get _severityLabel {
    switch (widget.diagnostic.severity) {
      case TefwayDiagnosticSeverity.info:
        return TefwayStrings.diagnosticsSeverityInfo;
      case TefwayDiagnosticSeverity.warning:
        return TefwayStrings.diagnosticsSeverityWarning;
      case TefwayDiagnosticSeverity.critical:
        return TefwayStrings.diagnosticsSeverityCritical;
    }
  }

  @override
  Widget build(BuildContext context) {
    final diagnostic = widget.diagnostic;
    final details = diagnostic.details;
    return Container(
      padding: const EdgeInsets.all(TefwaySpacing.md),
      decoration: BoxDecoration(
        color: TefwayColors.inputFill,
        borderRadius: TefwayRadius.mdAll,
        border: Border.all(color: _color.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icon, size: 16, color: _color),
              const SizedBox(width: TefwaySpacing.sm),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(diagnostic.title,
                        style: TefwayTextStyles.sectionTitle),
                    const SizedBox(height: 2),
                    Text(_severityLabel,
                        style: TefwayTextStyles.caption.copyWith(color: _color)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: TefwaySpacing.sm),
          Text(diagnostic.message, style: TefwayTextStyles.body),
          const SizedBox(height: TefwaySpacing.sm),
          _labelled(TefwayStrings.diagnosticsConsequence,
              diagnostic.consequence),
          if (diagnostic.action != null) ...[
            const SizedBox(height: 6),
            _labelled(TefwayStrings.diagnosticsAction, diagnostic.action!),
          ],
          if (details != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(
                  foregroundColor: TefwayColors.actionBlue,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(_expanded
                    ? TefwayStrings.hideDetails
                    : TefwayStrings.learnMore),
              ),
            ),
            if (_expanded)
              Text(details, style: TefwayTextStyles.bodySecondary),
          ],
          if (diagnostic.onAction != null && diagnostic.actionLabel != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: diagnostic.onAction,
                style: TextButton.styleFrom(
                  foregroundColor: TefwayColors.actionBlue,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(diagnostic.actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _labelled(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TefwayTextStyles.label),
        const SizedBox(height: 1),
        Text(value, style: TefwayTextStyles.bodySecondary),
      ],
    );
  }
}
