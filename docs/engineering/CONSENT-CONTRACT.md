# Consent Contract (Client side)

Normative contract for the window that asks the end user to accept a remote
session. Code that disagrees with this document is a bug; the document changes
only with a gate decision, never to match an implementation shortcut.

Files: `flutter/lib/tefway/consent.dart`,
`flutter/lib/desktop/pages/server_page.dart` (`buildTefwayConsentCard`),
`flutter/lib/tefway/strings.dart`, `src/server/connection.rs`,
`src/tefway/auth.rs`.

## 1. Invariants

These must hold after every change, including cosmetic ones:

1. **Local decision.** Nothing is shared until the user clicks in this window.
2. **Fail closed.** A missing, invalid, expired or replayed technician grant is
   refused by the core before this window is reachable. The UI never compensates
   for a core refusal.
3. **No new bypass.** The card does not call `sendLoginResponse`,
   `cmElevatePortable` or `cmSwitchPermission` directly. Every action goes
   through `checkClickTime(client.id, …)`, which confirms the click came from
   the local machine unless the deployment explicitly allows remote CM
   modification.
4. **Identity is never invented.** A name supplied by the peer is displayed as
   declared. It is never labelled verified unless the core verified it.
5. **Three actions, always.** Permitir, Recusar and Permitir com acesso elevado
   are always present. "Unavailable" changes the state of the third action, not
   its existence.

## 2. The three actions

| # | Label (pt-BR) | Callback | Core effect | When enabled |
| --- | --- | --- | --- | --- |
| 1 | `Permitir` | `onAllow` | `model.sendLoginResponse(client, true)` then `windowManager.minimize()` | always |
| 2 | `Recusar` | `onRefuse` | `bind.cmCloseConnection(connId)` | always |
| 3 | `Permitir com acesso elevado` | `onAllowAndElevate` | `sendLoginResponse(true)`, `setShowElevation(false)`, `bind.cmElevatePortable(connId)`, `windowManager.minimize()` | only when elevation is available for this session |

Rules:

- The three callbacks are independent. Elevating must never be routed through
  `onAllow`, and allowing must never elevate.
- The elevated action is **not** a preference and is never persisted. It applies
  to one session.
- When elevation is unavailable the button stays visible, is disabled
  (`onPressed == null`), and carries a visible reason plus a `Tooltip` with the
  same text. The reason is never hidden behind an icon alone.
- Refuse is always available, including while a permission is being changed.

Availability predicate (`buildTefwayConsentCard`):

```
canElevate = client.type_() == ClientType.remote
          && bind.cmCanElevate()
          && model.showElevation
          && builtin(kOptionHideElevateButtonInAcceptWindow) != 'Y'
```

Reasons shown when `canElevate` is false:

| Condition | Copy key |
| --- | --- |
| Not a desktop session (camera/file transfer) | `consentElevationDesktopOnly` |
| Platform has no elevation mechanism | `consentElevationUnsupported` |
| Elevation disabled for this session (option or session state) | `consentElevationSession` |

## 3. Identity

`tefwayIdentityVerified()` (`flutter/lib/tefway/branding.dart`) is true only
when the build is a Tefway product and the builtin option `tefway-auth-mode` is
`corporate`. `corporate` means `TEFWAY_AUTH_PUBKEY` is compiled in and
`authorize_login` rejects invalid grants in `src/server/connection.rs` before
the consent window is reachable. `pilot` means there is no trust anchor and the
normal RustDesk authentication applies.

| State | Chip | Detail |
| --- | --- | --- |
| verified | `Identidade verificada` (positive) | "A assinatura do técnico foi validada pelo núcleo antes desta janela." |
| not verified | `Identidade ainda não verificada` (attention) | "O nome acima foi informado pelo solicitante. Nenhum serviço de identidade validou esta sessão." |

The card also shows a permanent, positive security indicator: "Aprovação local
obrigatória — Nada é liberado sem o seu clique nesta janela." This is a statement
about the local gate, not about the peer.

## 4. Permissions

- The permission list is built from the live `Client` state, not from defaults:
  keyboard, clipboard, audio, file, restart, recording, Windows block-input,
  privacy mode (only when the platform supports an implementation), and the
  camera variant (audio, recording).
- Toggling calls `bind.cmSwitchPermission(connId, name, enabled)`. The core owns
  the state; the widget does not assume the change succeeded.
- The list is scrollable; the action footer is fixed. A long list must never
  push the actions out of reach.
- "Nada é liberado sem este clique" remains visible under the list.

## 5. Layout contract

The consent window is a small, resizable pane. The card must remain usable at:

| Constraint | Requirement |
| --- | --- |
| Minimum viewport | 300 × 490 logical px |
| Other viewports | 360×560, 440×620, 480×680, 1280×720, 1366×768, 1920×1080 |
| Text scale | 100%, 125%, 150% |
| Device pixel ratio | 1.0, 1.25, 1.5 |
| Content width | capped at 560 px, centred when wider |
| Long peer names | wrap, never overflow or clip the actions |
| Permission states | all on / all off render identically in structure |
| Elevation | available and unavailable both render all three actions |

Implementation rules:

- Header and action footer are outside the scroll view; only the requester and
  permissions cards scroll.
- Buttons use wrapping content (`Wrap`), not a fixed `Row`, so an icon plus a
  long label degrades by wrapping.
- Action buttons use a 44 px **minimum** height, never a fixed height: a fixed
  height clips wrapped content outside the button.
- A disabled action keeps a visible border and label; disabled is not conveyed
  by disappearing.
- Horizontal padding is `lg` below 360 px and `xl` above it.
- No layout may depend on the window being 440 px wide; that is a reference
  size, not a guarantee.

## 6. Copy

- Portuguese (pt-BR), sentence case, no exclamation marks.
- The title is "Solicitação de acesso remoto"; the subtitle says a technician
  wants to access this computer.
- Never say or imply "verificado" for a declared identity.
- Never promise that elevation is possible when it is not.
- Strings live in `flutter/lib/tefway/strings.dart`; the card contains no inline
  user-facing text.

## 7. Accessibility

- Every action is a real button with a label; disabled state is conveyed by the
  widget, not only by colour.
- The elevation reason is available both as visible text and as a tooltip.
- Status chips pair colour with an icon and text.
- The device ID is selectable so the user can read it back to support.
- Focus order follows the visual order: permissions, then Refuse, Permitir,
  Permitir com acesso elevado.

## 8. Test obligations

`flutter/test/tefway_consent_test.dart` must keep covering:

1. All three actions present, visible and independent at 300×490.
2. Elevation unavailable → visible, disabled, explained (text + tooltip).
3. Elevation available → enabled and not merged with allow.
4. Declared identity never shown as verified.
5. Core-verified identity shown as verified.
6. Permission switches call the real callback.
7. All required viewports × text scales × DPRs render without overflow.
8. Long names and every permission state do not overflow.
9. The footer stays reachable with a long permission list.

Rust side: `cargo test --lib --features flutter,linux-pkg-config tefway::`
must keep passing, including `auth_mode_option_matches_the_compiled_mode`.

## 9. Known limits

- The consent card does not display a cryptographically verified *name* in
  Pilot mode; it correctly says the identity is unverified. Showing a verified
  name in Corporate mode still depends on the grant being carried to the
  approval window.
- DPI scaling is exercised through device pixel ratio and text scale in widget
  tests. It is not a substitute for visual inspection on a HiDPI display.
- The elevated action is hidden entirely when the deployment sets
  `kOptionHideElevateButtonInAcceptWindow=Y`; that option is an explicit
  administrator decision, not a UI shortcut. The mission requirement (three
  buttons) applies to the default configuration.

## 10. Change protocol

A change to this contract requires:

1. A gate document under `docs/gates/` stating the new behaviour and why.
2. Updated tests that fail on the previous behaviour.
3. A Ponytail final review proving the diff does not add state or a bypass.
4. Re-validation of the AppImage runtime, because the consent window is the
   first thing an incoming session shows.
