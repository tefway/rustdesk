# UX-04 — Central de Diagnósticos and Client surface

## 1. Problem

The Client rendered every platform condition as a full-width card on the home
surface (UAC, Wayland, login-Wayland, SELinux), whether or not anything was
wrong. Wayland being active and SELinux being enforcing were presented like
faults, the cards consumed the vertical space of a 744 px window, and the list
was built as ready-made widgets, so it could not be counted, sorted, de-duplicated
or tested.

## 2. Model (`flutter/lib/tefway/diagnostics_model.dart`)

Pure Dart, no FFI or platform imports, so it is testable on the VM.

| Field | Purpose |
| --- | --- |
| `id` | stable key; duplicates collapse (`putIfAbsent`) |
| `severity` | `info` / `warning` / `critical` |
| `title`, `message` | what was detected |
| `consequence` | what it means for the attendance |
| `details` | technical explanation, expandable |
| `action` | recommended action, only when one is real |
| `actionLabel` + `onAction` | a safe action that actually runs (core retry) |
| `blocksSession` | true only for a core-reported failure |

Severity rules:

- Wayland active → **info**: capture depends on the portal; it is not a proven
  failure.
- SELinux enforcing → **info**: a policy may deny; only the admin's log proves it.
- Login screen under Wayland → **warning**: capture of the login screen is not
  available in that configuration.
- UAC on Windows → **info**: elevated windows may ignore remote input.
- A non-empty `mainGetError()` → **critical**, blocking, with a real retry.

`flutter/lib/tefway/notices.dart` is the thin adapter: it asks the core
(`mainCurrentIsWayland`, `mainIsLoginWayland`, `isSelinuxEnforcing`,
`mainGetError`) and hands the values to the pure builder. No condition is
inferred from the platform name alone.

## 3. UI (`flutter/lib/tefway/diagnostics.dart`)

- `TefwayDiagnosticsButton` sits in the header (`TefwayBrandHeader.trailing`),
  the same place on every surface. The count is `diagnostics.length`, never a
  stored value; the badge is hidden at zero and coloured by the worst severity.
- `showTefwayDiagnostics` opens a constrained (`maxWidth 560`, `maxHeight 620`)
  scrollable panel: title, count, severity label per entry, message,
  consequence, recommended action, `Saiba mais` for technical details and a
  retry button only when `onAction` exists.
- Empty state is neutral ("Nenhum diagnóstico pendente").
- Footer states that the panel informs and never disables a security check.
- `Semantics` + `Tooltip` carry the count for screen readers.

## 4. Client surface

- Header now carries brand, product name, subtitle and the diagnostics button.
- The platform cards are gone from the main column; spacing was reduced
  (`xs`/`sm` instead of repeated `md`) so the content fits 440×744 and the
  1280×720 case still works with the existing `_fitToScreen()` clamp.
- A blocking core error remains **in the flow** as `TefwayCoreErrorNotice`, in
  addition to its entry in the panel, as required for blocking failures.
- ID, copy, availability, guidance, AGPL attribution and footer are unchanged in
  meaning.

## 5. Consent

`TefwayConsentCard` now states, under the requester's name and ID:
"Nome informado pelo solicitante. A identidade do técnico é verificada pelo
núcleo antes de qualquer liberação." A declared name is never presented as a
verified identity. The card still cannot grant anything: `onAllow` remains bound
to the existing `checkClickTime` guard in `server_page.dart`, and the core now
rejects an unverified peer before the card is reachable.

Showing the verified technician name in the card is pending (the verified
identity is not yet carried to the approval window).

## 6. Verification

| Check | Result |
| --- | --- |
| `flutter test test/tefway_diagnostics_test.dart` | PASS — 8/8 |
| duplicates collapse, ids unique | PASS |
| Wayland/SELinux are `info`, not failures | PASS |
| core error is `critical`, blocking, retryable | PASS |
| count follows list, critical sorts first | PASS |
| `flutter analyze` on touched files | no findings |
| Visual inspection (1280×720, 1366×768, 125%/150%, large fonts) | NOT_DONE — no screenshot was taken |
| Master login/authenticated states | NOT_DONE — depends on AUTH-01 login surface |

`UX_04_RESPONSIVE = NOT_TESTED`, `UX_04_DIAGNOSTICS = PARTIAL` (logic tested,
rendering not inspected), `UX_04_CONSENT = PARTIAL`.
