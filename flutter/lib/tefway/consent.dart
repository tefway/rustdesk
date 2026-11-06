// Tefway consent surface for an incoming session.
//
// Presentation only: the accept/refuse/permission calls stay in
// `desktop/pages/server_page.dart`, next to the click-tampering guard the core
// window already relies on. This widget must never grant anything on its own.

import 'package:flutter/material.dart';

import 'design.dart';
import 'strings.dart';
import 'widgets.dart';

/// Why the elevated action is disabled for this session, or null when it is
/// available. Each false input has a distinct cause and its own copy, so a
/// missing mechanism is never reported as an administrator decision.
String? tefwayElevationUnavailableReason({
  required bool desktopSession,
  required bool mechanismSupported,
  required bool sessionAllows,
  required bool hiddenByPolicy,
}) {
  if (!desktopSession) return TefwayStrings.consentElevationDesktopOnly;
  if (!mechanismSupported) return TefwayStrings.consentElevationUnsupported;
  if (hiddenByPolicy) return TefwayStrings.consentElevationPolicy;
  if (!sessionAllows) return TefwayStrings.consentElevationSession;
  return null;
}

/// One capability the remote side is asking for, with its current state.
class TefwayCapability {
  const TefwayCapability({
    required this.key,
    required this.label,
    required this.icon,
    required this.enabled,
  });

  /// Permission name understood by the core (`cmSwitchPermission`).
  final String key;
  final String label;
  final IconData icon;
  final bool enabled;
}

class TefwayConsentCard extends StatefulWidget {
  const TefwayConsentCard({
    super.key,
    required this.peerName,
    required this.peerId,
    this.verifiedName,
    required this.capabilities,
    required this.onToggle,
    required this.onAllow,
    required this.onRefuse,
    this.onAllowAndElevate,
    this.elevationUnavailableReason,
  });

  /// Name declared by the peer. Displayed only when the core did not verify an
  /// identity for this session.
  final String peerName;
  final String peerId;

  /// Name carried by the technician grant the core verified for this session.
  /// Null or blank means no verified identity is available, and the card must
  /// say so instead of presenting the declared name as authenticated.
  final String? verifiedName;
  final List<TefwayCapability> capabilities;
  final void Function(String key, bool enabled) onToggle;
  final VoidCallback onAllow;
  final VoidCallback onRefuse;

  /// Null means this platform cannot elevate. The action stays visible and
  /// disabled, with [elevationUnavailableReason] as the explanation.
  final VoidCallback? onAllowAndElevate;
  final String? elevationUnavailableReason;

  @override
  State<TefwayConsentCard> createState() => _TefwayConsentCardState();
}

class _TefwayConsentCardState extends State<TefwayConsentCard> {
  late final Map<String, bool> _enabled = {
    for (final capability in widget.capabilities) capability.key: capability.enabled,
  };

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: TefwayColors.deepNavy,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal =
              constraints.maxWidth < 360 ? TefwaySpacing.lg : TefwaySpacing.xl;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                children: [
                  _header(horizontal),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(horizontal, TefwaySpacing.md,
                          horizontal, TefwaySpacing.md),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _requesterCard(),
                          const SizedBox(height: TefwaySpacing.md),
                          _permissionsCard(),
                          const SizedBox(height: TefwaySpacing.md),
                          Text(
                            TefwayStrings.consentSessionNote,
                            style: TefwayTextStyles.caption,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _actions(horizontal),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _header(double horizontal) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          horizontal, TefwaySpacing.lg, horizontal, TefwaySpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TefwayBrandHeader(
            title: TefwayStrings.consentTitle,
            subtitle: TefwayStrings.consentSubtitle,
            markSize: 44,
            titleStyle: TefwayTextStyles.appTitle.copyWith(fontSize: 17),
          ),
          const SizedBox(height: TefwaySpacing.sm),
          const TefwayStatusChip(
            status: TefwayStatus.attention,
            label: TefwayStrings.consentWaiting,
          ),
        ],
      ),
    );
  }

  Widget _requesterCard() {
    final verifiedName = widget.verifiedName?.trim() ?? '';
    final verified = verifiedName.isNotEmpty;
    return TefwaySurfaceCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(TefwayStrings.consentPeerLabel, style: TefwayTextStyles.label),
          const SizedBox(height: TefwaySpacing.xs),
          Text(verified ? verifiedName : widget.peerName,
              style: TefwayTextStyles.sectionTitle),
          const SizedBox(height: TefwaySpacing.xs),
          Text(TefwayStrings.consentPeerIdLabel,
              style: TefwayTextStyles.caption),
          const SizedBox(height: 2),
          SelectableText(
            widget.peerId,
            style: TefwayTextStyles.caption.copyWith(
              color: TefwayColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: TefwaySpacing.md),
          TefwayStatusIndicator(
            status: verified ? TefwayStatus.positive : TefwayStatus.attention,
            label: verified
                ? TefwayStrings.consentIdentityVerified
                : TefwayStrings.consentIdentityUnverified,
            detail: verified
                ? TefwayStrings.consentIdentityVerifiedDetail
                : TefwayStrings.consentIdentityUnverifiedDetail,
          ),
          const SizedBox(height: TefwaySpacing.md),
          Text(TefwayStrings.consentSecurityTitle,
              style: TefwayTextStyles.label),
          const SizedBox(height: TefwaySpacing.xs),
          const TefwayStatusIndicator(
            status: TefwayStatus.positive,
            label: TefwayStrings.consentSecurityLocalApproval,
            detail: TefwayStrings.consentSecurityLocalApprovalDetail,
            compact: true,
          ),
        ],
      ),
    );
  }

  Widget _permissionsCard() {
    return TefwaySurfaceCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(TefwayStrings.consentCapabilities,
              style: TefwayTextStyles.label),
          const SizedBox(height: 2),
          Text(TefwayStrings.consentCapabilitiesHint,
              style: TefwayTextStyles.bodySecondary),
          const SizedBox(height: TefwaySpacing.sm),
          for (final capability in widget.capabilities)
            _capabilityRow(capability),
          const SizedBox(height: TefwaySpacing.sm),
          Text(TefwayStrings.consentNote,
              style: TefwayTextStyles.bodySecondary),
        ],
      ),
    );
  }

  Widget _actions(double horizontal) {
    final elevate = widget.onAllowAndElevate;
    final reason = widget.elevationUnavailableReason ??
        TefwayStrings.consentElevationUnsupported;
    final elevateButton = TefwaySecondaryButton(
      label: TefwayStrings.consentAllowElevate,
      icon: Icons.security_rounded,
      onPressed: elevate,
    );
    // A fixed height clips the icon/label when the text wraps; keep 44 px as a
    // minimum touch target and let the button grow with its content.
    Widget action(Widget child) => ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: child,
        );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          horizontal, TefwaySpacing.md, horizontal, TefwaySpacing.md),
      decoration: const BoxDecoration(
        color: TefwayColors.deepNavy,
        border: Border(top: BorderSide(color: TefwayColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: action(TefwaySecondaryButton(
                    label: TefwayStrings.consentRefuse,
                    icon: Icons.block_rounded,
                    onPressed: widget.onRefuse,
                  )),
                ),
                const SizedBox(width: TefwaySpacing.md),
                Expanded(
                  child: action(TefwayPrimaryButton(
                    label: TefwayStrings.consentAllow,
                    icon: Icons.check_rounded,
                    onPressed: widget.onAllow,
                  )),
                ),
              ],
            ),
          ),
          const SizedBox(height: TefwaySpacing.sm),
          action(elevate == null
              ? Tooltip(message: reason, child: elevateButton)
              : elevateButton),
          if (elevate == null) ...[
            const SizedBox(height: TefwaySpacing.xs),
            Text(
              reason,
              style: TefwayTextStyles.caption,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _capabilityRow(TefwayCapability capability) {
    final enabled = _enabled[capability.key] ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(
            capability.icon,
            size: 16,
            color:
                enabled ? TefwayColors.textPrimary : TefwayColors.textSecondary,
          ),
          const SizedBox(width: TefwaySpacing.sm),
          Expanded(
            child: Text(
              capability.label,
              style: enabled
                  ? TefwayTextStyles.body
                  : TefwayTextStyles.bodySecondary,
            ),
          ),
          Switch.adaptive(
            value: enabled,
            onChanged: (value) {
              setState(() => _enabled[capability.key] = value);
              widget.onToggle(capability.key, value);
            },
          ),
        ],
      ),
    );
  }
}
