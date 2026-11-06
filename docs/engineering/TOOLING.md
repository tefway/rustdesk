# Engineering Tooling

How this repository is analysed, reviewed and packaged. Every command here was
executed on the UX-05 branch unless marked as a fallback. The point of this file
is that the next person can reproduce the evidence without guessing.

## 1. Graphify (code graph)

Graphify turns the tree into a queryable graph. It is the first step for any
architecture question: it answers "what calls this", "what breaks if I change
this" and "where is this flow implemented" from the code, not from memory.

| Item | Value |
| --- | --- |
| Version | `graphify 0.9.93` |
| Binary | `~/.local/bin/graphify` |
| Graph | `graphify-out/graph.json` (local artifact, gitignored) |
| Manifest | `graphify-out/manifest.json` (incremental cache metadata) |
| Size at UX-05 | 22,240 nodes, 42,732 edges |

Build / refresh:

```bash
# Full code-only extraction, no clustering (fast, no API key)
graphify extract . --code-only --no-cluster

# Incremental update after code changes
graphify update .
```

Query:

```bash
graphify query "how does an incoming session reach the Tefway consent card" \
  --graph graphify-out/graph.json
graphify explain "TefwayConsentCard" --graph graphify-out/graph.json
graphify path "A" "B" --undirected --graph graphify-out/graph.json
```

Notes:

- `--code-only` indexes ASTs locally and skips docs, papers and images. It needs
  no API key, which is why it is the default for this repository.
- `--no-cluster` skips community detection and label generation. Clustering is
  useful for a human-readable report, not for call-chain questions, and it is
  the slow/LLM-backed part.
- The graph is an artifact: do not commit `graphify-out/`. Re-run the command on
  a fresh checkout instead.
- `graphify query` truncates output at a token budget. When the answer may be in
  the cut nodes, re-run with `--budget <n>` or narrow the seed.

## 2. Context7 (library documentation)

Context7 provides version-aware documentation snippets for third-party
libraries. There is no MCP server configured in this environment, so the REST
API is used directly:

```bash
# Find the library id
curl -fsS "https://context7.com/api/v1/search?query=window_manager%20flutter"

# Fetch documentation for a topic
curl -fsS "https://context7.com/api/v1/leanflutter/window_manager?type=txt&topic=setSize%20center"
```

The npm package `@upstash/context7-mcp` is available if an MCP server is
preferred, but it is not required for the commands above.

Libraries queried for UX-05:

| Library | Id | What was taken from it |
| --- | --- | --- |
| window_manager | `/leanflutter/window_manager` | `setSize`/`center`/`waitUntilReadyToShow` semantics; the window is shown only after options are applied |
| Flutter framework | `/websites/flutter_dev` | text scaling (`textScaleFactor`/`TextScaler`), `SingleChildScrollView` + `ConstrainedBox` layout rules, `FittedBox` behaviour |
| Rust anyhow | `/websites/rs_anyhow` | `Context`/`with_context`/`bail!` error propagation used by the core |
| AppImage | `/websites/appimage` | type-2 runtime is a separate file; `APPIMAGE_EXTRACT_AND_RUN` for FUSE-less execution |

Rule: Context7 is used to confirm API behaviour, never as the source of a
security decision. Security decisions come from the code and from the gate
documents in `docs/gates/`.

## 3. Skills

Skills are loaded with the harness `skill` tool before the work they govern, not
after. The registry — what exists, when to use it, what was applied in UX-05 —
is `docs/engineering/SKILLS-REGISTRY.md`.

## 4. Ponytail (diff discipline)

Ponytail is not an opencode command in this environment; its skill files live at
`~/.claude/plugins/marketplaces/ponytail/skills/`. It is applied manually in
`full` mode, before implementation and again on the final diff.

The checklist that must hold for every change:

1. Is the diff the smallest one that fixes the reported behaviour?
2. Is existing code reused instead of duplicated or reshaped?
3. Are new dependencies avoided? (No new package was added for UX-05.)
4. Is new state avoided? (UX-05 added no new mutable state; the identity flag is
   a read of a builtin option.)
5. Are the three consent actions still independent and always present?
6. Does the feature-off path still run the old code?

`PONYTAIL_FINAL_REVIEW` in the gate report is the second pass over the final
`git diff`, not a restatement of the pre-review.

## 5. Impeccable (UI review)

The launcher `~/.agents/skills/impeccable/scripts/impeccable` is not installed
on this machine, so the UI review used the repository's own design contract:
`docs/design/TEFWAY-REMOTE-DESIGN-SYSTEM.md` plus the component inventory in
`flutter/lib/tefway/widgets.dart`. If the launcher becomes available, run it
against the consent card before changing its layout.

## 6. Linux AppImage toolchain

The builder is a pinned container image; the host only needs Podman.

| Component | Pin | Where |
| --- | --- | --- |
| Builder image | `localhost/tefway-linux-builder:bookworm-rust1.99.1-flutter3.44.8` | built from `docker/tefway-linux/Dockerfile` |
| Rust | 1.99.1 | Dockerfile base image |
| Flutter | 3.44.8 (SHA-256 pinned) | Dockerfile |
| flutter_rust_bridge_codegen | 1.80.1 (SHA-256 pinned) | Dockerfile |
| appimagetool | 1.9.1 (SHA-256 pinned) | Dockerfile |
| linuxdeploy | 1-alpha-20251107-1 (SHA-256 pinned) | Dockerfile |
| AppImage type-2 runtime | release `20251108`, SHA-256 `2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d` | `docker/tefway-linux/build.sh` |

### Runtime cache (fix for the packaging-time HTTP 504)

`appimagetool` normally downloads the type-2 runtime itself. That download is
not reproducible and failed with HTTP 504. `build.sh` now does this instead:

1. `ensure_appimage_runtime()` runs on the host, before the container starts.
2. The cache path is `build/tefway/appimage-runtime-x86_64` (gitignored).
3. An existing file is reused only if its SHA-256 matches the pin; a mismatching
   file is deleted, not reused.
4. A missing file is downloaded with `curl --retry 3` and verified before it is
   moved into place (`*.part` → final name).
5. Inside the container, `build_appimage()` re-verifies the same SHA-256 and
   passes `--runtime-file /work/build/tefway/appimage-runtime-x86_64`.
6. The manifest records `appimage_runtime.version` and `.sha256`.

`TEFWAY_APPIMAGE_RUNTIME_URL` can point at a mirror; the checksum still has to
match, so a mirror cannot change the runtime.

Build:

```bash
./docker/tefway-linux/build.sh --profile client --skip-image
./docker/tefway-linux/build.sh --profile master --skip-image
```

Verify an artifact:

```bash
sha256sum build/tefway/client/TefwayRemoteClient-Linux-x86_64.AppImage
jq . build/tefway/client/TefwayRemoteClient-Linux-x86_64.AppImage.manifest.json
```

The build itself checks the AppDir layout, unresolved libraries (`ldd`),
`RUNPATH=$ORIGIN/lib` and the presence of the Flutter engine and assets. A
layout regression fails the build instead of shipping a broken AppImage.

## 7. Evidence hygiene

- A status is `PASS` only when a command or a test in this repository produced
  the result in this work session.
- Indirect evidence is `PARTIAL`; no execution at all is `NOT_TESTED`.
- Screenshots, tool runs and runtime checks are described with the exact command
  and output location, so they can be re-run.
- Widget tests count as layout evidence for the sizes and text scales they
  assert. They do not count as visual inspection of the final binary.
