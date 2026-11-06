# Skills Registry

The harness exposes skills through the `skill` tool. A skill is a set of
instructions plus optional resources; load it before doing the work it governs,
not after. This registry records what exists, when each one applies and whether
it was used in the UX-05 gate.

## 1. How to load a skill

```
skill({ id: "<id>" })
```

Loading is cheap and idempotent. A skill that is already present in the
conversation (for example because the user invoked it) does not need to be
loaded again.

## 2. Inventory

| Skill id | Scope | Use when | UX-05 |
| --- | --- | --- | --- |
| `graphify` | Code graph / architecture | Any question about a codebase, its architecture or file relationships; first step when `graphify-out/` exists | **Applied** — built the graph and queried the consent path |
| `rust-review` | Rust security review | Reviewing Rust for memory safety, concurrency, FFI, async, panic-DoS | **Applied** — reviewed `src/tefway.rs`, `src/tefway/auth.rs`, `src/server/connection.rs` |
| `impeccable` | Frontend design/UX | Designing, critiquing, polishing a UI; accessibility, responsive, hierarchy | **Applied with fallback** — launcher missing, used the repo design system |
| `systematic-debugging` | Debugging method | Any bug, failing test or unexpected behaviour, before proposing a fix | **Applied** — AppImage runtime HTTP 504 |
| `test-driven-development` | Implementation method | Implementing a feature or bugfix, before writing implementation code | **Applied** — consent widget tests written against the contract |
| `verification-before-completion` | Evidence discipline | Before claiming work is complete/fixed/passing | **Applied** — every gate status checked against a command |
| `writing-plans` | Planning | Multi-step task with a spec, before touching code | **Applied** — gate plan before implementation |
| `requesting-code-review` | Review handoff | Completing a task or before merging | Consulted — review done in-tree; no external reviewer in this run |
| `differential-review` | Diff security review | Security-focused review of a change set with git history and blast radius | Consulted — used for the regression-surface pass |
| `spec-to-code-compliance` | Spec vs code | Checking code against the documentation that specifies it | Consulted — consent contract vs implementation |
| `security-audit` | Security audit | Explicit codebase audit or pen-test request | Not applicable — this gate is a UX/build gate, not an audit |
| `property-based-testing` | Property tests | Writing or triaging property-based tests | Not applicable — no property harness in this tree |
| `code-security` | Secure coding | Writing code that handles input, auth, files, queries, crypto, infra | Consulted — consent actions are auth-adjacent |
| `react-best-practices` | React / Next.js | React or Next.js performance work | Not applicable — Flutter UI |
| `vue-quasar-best-practices` | Vue 3 + Quasar | LumosPOS frontend work | Not applicable — different product |
| `reverse-engineer-anything` | Reverse engineering | Shipped-artifact or runtime analysis | Not applicable — source is available |
| `browser` | In-app browser | Reading pages, clicking, screenshots, console/network logs | Not applicable — no web surface in this gate |
| `report` | Issue reporting | Reporting an OpenCode bug with diagnostics | Not applicable |
| `opencode` | OpenCode itself | Questions about OpenCode config, SDK, agents, tools | Not applicable |

## 3. Ponytail

Ponytail is not exposed as a harness skill in this environment. It lives at
`~/.claude/plugins/marketplaces/ponytail/skills/` and is applied manually in
`full` mode (see `TOOLING.md` §4). Both passes are required:

- **Pre-review**: before implementation, to choose the smallest design.
- **Final review**: on the finished `git diff`, to remove anything that is not
  required by the reported behaviour.

## 4. Selection rule

Load the skill that matches the *risk* of the change, not the file type:

- Touching authentication, consent or the wire protocol → `rust-review` and
  `code-security`.
- Touching a screen → `impeccable` (or the repo design system when the launcher
  is unavailable).
- Chasing a failure → `systematic-debugging` before any fix.
- About to declare a gate green → `verification-before-completion`.
- Starting from a spec → `writing-plans`.

Do not load every skill for every task. The registry is a map, not a checklist.
