# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Podman Quadlet unit files and installable wrapper scripts that run two MCP
(Model Context Protocol) servers: Kubernetes as a rootless, per-user systemd
service, and GitHub as a per-connection `podman run` spawned by an MCP
client (see "Transport caveat" in README.md — `github-mcp-server` only
supports the `stdio` transport, which doesn't fit a long-lived systemd
unit). A Makefile/`hack` harness lints, generates, installs, and uninstalls
all of it. It is a deployment/config repo, not an application — there is no
application source code to build or run, only unit files, shell scripts,
and bats tests.

## Commands

See README.md "Usage" (or run `make help`) for the full make-target list
with one-line descriptions.

Run a single test file or case directly with bats (skip the Makefile's
submodule check if already fetched):

```bash
test/vendor/bats-core/bin/bats test/install.bats
test/vendor/bats-core/bin/bats test/install.bats -f "never overwrites"
```

`quadlet` must be present at `/usr/libexec/podman/quadlet` or
`/usr/lib/podman/quadlet` (Fedora: part of the `podman` package) for
`lint`/`generate`/`test` to work; override with `QUADLET_BIN=/path/to/quadlet`.

`kcov` must be installed for `make coverage` to work; override with
`KCOV_BIN=/path/to/kcov`. It's a separate, heavier run than `make test` --
kcov traces every bash process the bats suite forks, so expect it to take
noticeably longer than a plain `make test`. Its bash line-tracer is also
unreliable across forked/exec'd children: `hack/*.sh` is consistently
covered, but `home/bin/*` scripts (run as subprocesses by e.g.
`kubernetes-mcp-kubeconfig-secret.bats`) consistently don't show up in
the report even when the tests exercise and pass them -- a kcov
limitation, not a real coverage gap. See the comment on `run_coverage()`
in `hack/coverage.sh` for what was ruled out.

## Architecture

**`home/` holds everything that ends up under the user's `$HOME`; `hack/`
never does.** `home/` mirrors destination roots the same way `config/` used
to at repo root: `home/config/` → `$XDG_CONFIG_HOME` (usually `~/.config`),
`home/bin/` → `~/.local/bin`, `home/lib/` → `~/.local/lib/podrc`.
Everything under one of those three lands at the identical relative path
under its destination when installed — don't add files there that aren't
meant to be installed verbatim. `hack/` is the opposite: the lint/generate/
install/uninstall harness that operates *on* `home/`, never installed
itself, always run from the repo checkout.

**`home/bin/` vs `home/lib/`.** `home/bin/*` are standalone, directly
executable entry points (installed mode `0744` by `make install-local`),
deliberately named without a `.sh` suffix since they're meant to be run
as plain commands once on `PATH` (`github-mcp-server-stdio`,
`kubernetes-mcp-kubeconfig-secret`). `home/lib/podrc/*` is for library
code a `home/bin/` script sources rather than runs — installed mode
`0644` (never executable) to `~/.local/lib/podrc`. The `podrc/`
subdirectory under `home/lib/` exists purely so the installed
`~/.local/lib/podrc` destination sits one level below a plain
`~/.local/lib/<file>`, avoiding collisions with other tools' files
there — `home/lib/podrc/` and `~/.local/lib/podrc/` mirror each other
1:1 like `home/bin/` and `~/.local/bin/` do. Neither is `hack/common.sh`:
that's dev-harness-only and never installed at all.

**`env/*.example` is a separate, non-mirrored path** — despite the
directory's name, it holds both env-file and config-file templates (e.g.
`env/etc/kubernetes-mcp-server/config.toml.example` and
`conf.d/*.toml.example` alongside the `*.env.example` files). `make
install` copies every `*.example` file under `env/` (except
`env/environment.d/`, installed separately — see below) into
`~/.config/podrc/`, recursively and preserving the path relative to
`env/`, stripping only the `.example` suffix — e.g.
`env/etc/kubernetes-mcp-server/conf.d/00-base.toml.example` lands at
`~/.config/podrc/etc/kubernetes-mcp-server/conf.d/00-base.toml`. It skips
any destination that already exists, so a reinstall never clobbers a
filled-in secret or hand-edited config — there's no separate git-ignored
overlay directory that a reinstall mirrors; the user's real files live
directly under `~/.config/podrc/` and are edited there. This is why these
templates live outside `home/config/` instead of being mirrored — a
mirror would tempt clobbering real values on reinstall.

**The `-systemd.env` / `-systemd.env.example` suffix marks the `[Service]`
side of that split.** A plain `<name>.env(.example)` is referenced by
`EnvironmentFile=` in a unit's `[Container]` section — those values become
environment variables inside the running container. A
`<name>-systemd.env(.example)` is referenced by `EnvironmentFile=` in the
same unit's `[Service]` section instead — read by systemd itself, not
passed into the container — for values a unit needs outside the container,
e.g. a podman secret name interpolated into a `Secret=` line in
`[Container]`, or a value checked by an `ExecStartPre=` guard. All of
these files still land in the same `~/.config/podrc/` directory on
install; only the suffix distinguishes which unit section reads them.

**A non-`.env` template (e.g. `env/etc/kubernetes-mcp-server/config.toml.example`)
is neither of those** — it's not `EnvironmentFile=`'d in at all. Its whole
installed directory is bind-mounted straight into the container by a
`Volume=` line in the `.container` unit, at the in-container path its
sibling `-systemd.env`/`Exec=` config points the relevant flag (e.g.
`--config`) at. `install_env_templates()` in `hack/install.sh` finds
`*.example` recursively under `ENV_EXAMPLE_DIR` (not just top-level, and
not just `*.env.example`) specifically so this kind of nested template
gets picked up too — keep that in mind if adding a new template that
isn't a flat `.env` file.

**`env/environment.d/*.example` is a third, separate template path**,
parallel to `env/*.example` but for a different destination and reader:
`env/environment.d/podrc.conf.example` installs (same skip-if-exists rule)
to `~/.config/environment.d/podrc.conf`, read by systemd --user's
environment.d generator (`environment.d(5)`) at session start, not by any
Quadlet unit's `EnvironmentFile=`. It's opt-in and unrelated to running the
MCP servers — everything else in this repo already falls back to
`~/.config` on its own when `XDG_CONFIG_HOME` is unset — so it has its own
scripts/make targets (`hack/install-session-env.sh` /
`hack/uninstall-session-env.sh`, `make install-session-env` /
`make uninstall-session-env`) instead of being folded into
`install.sh`/`uninstall.sh`. See README.md "Session-wide XDG_CONFIG_HOME".

**`hack/install-claude-mcp.sh` / `hack/uninstall-claude-mcp.sh`** register
this repo's two MCP servers with Claude Code's own `claude mcp` config —
`kubernetes-mcp` as a user-scope `--transport http` server pointed at
`http://127.0.0.1:8081/mcp` (the Kubernetes service's `PublishPort=`, plus
the `/mcp` Streamable HTTP path noted in README.md "Configuring each
server"), `mcp-github` as a user-scope stdio server pointed at the
installed `~/.local/bin/github-mcp-server-stdio` (skipped with a warning if
`install-local.sh` hasn't run yet). This is a fourth, separate opt-in
scripts/make-targets pair (`make install-claude-mcp` / `make
uninstall-claude-mcp`), same rationale as `install-session-env.sh`: it
writes to state this repo doesn't otherwise touch (Claude Code's own
config, not `~/.config/podrc`) and depends on the `claude` CLI being
present, so it's not folded into `install.sh`/`uninstall.sh` either.
Registering a name that already exists is a no-op (logged, not an error)
— run `claude mcp remove <name> -s user` first to reconfigure one; this
mirrors the skip-if-exists behavior of the `env/*.example` templates
rather than `install-local.sh`'s always-overwrite behavior.

**`hack/common.sh`** is sourced (not executed) by every other script in
`hack/`; it defines the readonly globals `SCRIPT_DIR`, `REPO_ROOT`,
`QUADLET_SRC_DIR`, `QUADLET_UNIT_SUFFIXES`, `ENV_EXAMPLE_DIR`,
`ENVIRONMENT_D_EXAMPLE_DIR`, `HOME_BIN_SRC_DIR`,
`HOME_LIB_SRC_DIR`, and the functions `init_logging()`,
`resolve_quadlet_bin()`, `install_config_dir()`, `install_env_dir()`,
`install_environment_d_dir()`, `install_bin_dir()`, `install_lib_dir()`,
plus a set of quadlet-unit-introspection helpers that derive
service/container/network
names from the unit files themselves instead of hardcoding them:
`list_quadlet_units()` (every unit file matching `QUADLET_UNIT_SUFFIXES` in
`QUADLET_SRC_DIR`), `container_service_names()` (the `<name>.service`
Quadlet generates per `*.container` unit), `quadlet_container_names()`/
`quadlet_network_names()` (the podman container/network name Quadlet
creates per `*.container`/`*.network` unit -- its `ContainerName=`/
`NetworkName=` value if set, else the unit's own basename), and the
`quadlet_unit_value()` / `resolve_unit_specifiers()` helpers those two use
to read a unit's `key=value` lines and expand the `%N` systemd specifier.
New scripts should source `common.sh` the same way rather than recomputing
any of this — this applies to `hack/*.sh` only; `home/bin/*` scripts
deliberately don't (see the stdio-purity note in
`home/bin/github-mcp-server-stdio`).

**`vendor/bash-logger`** (git submodule, `git@github.com:s-fairchild/bash-logger.git`)
provides the `log_debug`/`log_info`/`log_warn`/`log_error`/... functions
every script uses instead of raw `echo` for status output. Each entry
point's `main()` calls `init_logging()` (defined in `common.sh`) as its
first step, which sources `vendor/bash-logger/logging.sh` and calls its
`init_logger`, shielded from `set -e` — see the comment on `init_logging()`
for why that shielding is load-bearing. `make lint`/`generate`/`install`/
`uninstall` all depend on the `submodules` Makefile target, which now also
checks for `vendor/bash-logger/logging.sh` before fetching.

**`lint.sh` / `generate.sh` never touch real systemd paths.** Both point
the local `quadlet` binary at this repo's `home/config/containers/systemd/`
via the `QUADLET_UNIT_DIRS` env var (which `quadlet` itself supports for
this purpose) and dry-run into a throwaway/`.generated` dir. Only
`install.sh` and `uninstall.sh` write to real paths, and only under
`$XDG_CONFIG_HOME` — never as root, never outside the user's own config.
`install-local.sh` writes to `~/.local/bin` and
`~/.local/lib/podrc` — also never as root. `install-session-env.sh` /
`uninstall-session-env.sh` write to `$XDG_CONFIG_HOME/environment.d` —
same real-path caveat, and likewise never as root. `install-claude-mcp.sh` /
`uninstall-claude-mcp.sh` write to the `claude` CLI's own user-scope MCP
config (outside this repo's paths entirely) via `claude mcp add`/`remove`
— same real-path caveat, and likewise never as root.

**Test isolation (`test/test_helper.bash`)**: `setup_sandbox` redirects
`HOME`/`XDG_CONFIG_HOME` into a `mktemp -d` sandbox and prepends
`test/fixtures/bin/` onto `PATH`: a fake `systemctl` that just logs its
argv to `SYSTEMCTL_STUB_LOG` instead of touching the real user systemd
manager, and a fake `claude` that implements just the `mcp add`/`get`/
`remove` subset `install-claude-mcp.sh`/`uninstall-claude-mcp.sh` use,
tracking registered server names as files under `CLAUDE_STUB_STATE_DIR`
(logging argv to `CLAUDE_STUB_LOG`) instead of touching the real
`~/.claude.json`. Any bats test exercising `install.sh`/`uninstall.sh`
must call `setup_sandbox` in `setup()` and `teardown_sandbox` in
`teardown()`. Tests override `QUADLET_SRC_DIR` to point at
`test/fixtures/bad-quadlets/` to exercise the lint-failure path without
touching the real quadlet units.

**Test deps are git submodules** (`test/vendor/{bats-core,bats-support,bats-assert}`),
not vendored copies — `make test`/`make submodules` runs
`git submodule update --init --recursive` automatically if
`test/vendor/bats-core/bin/bats` isn't executable yet.

**`kubernetes-mcp-server.container`'s `Image=` points at a sibling `.image` unit**
(`kubernetes-mcp-server.image`), not a bare registry reference — Quadlet
resolves the `.image` suffix to that unit, generates
`kubernetes-mcp-server-image.service` to pull it, and auto-adds the
`Requires=`/`After=` dependency on the `.container`'s generated service.
The actual `podman pull`-equivalent image reference lives in the
`[Image]` section of the `.image` file, so change it there, not in the
`.container` file. `github-mcp-server.image` has no `.container` pointing
at it — nothing Quadlet-managed runs the GitHub server (see below) — it
exists standalone purely to keep that image pulled/current.

**`kubernetes-mcp-server.container` is intentionally incomplete**
(`TODO(verify)` comments in it and in `kubernetes-mcp-server.image`): MCP
servers are normally spawned per-connection over stdio, which doesn't fit
a long-lived systemd unit. This unit assumes the container image supports
a persistent SSE/HTTP transport flag instead (`--transport sse --port
<N>`), but the exact flag and which of several same-named community
images to use must be verified against the real image's `--help` output
before this is production-usable. See README.md "Transport caveat" before
changing `Image=` (in the `.image` file) or `Exec=` (in the `.container`
file). README.md "Configuring each server" links the image's upstream
repo and lists which of its env vars/flags this repo currently sets vs.
leaves at defaults — check it before adding new keys to
`env/kubernetes-mcp*.env.example`, and note it already flags that the
Kubernetes server's real flag is `--port` (Streamable HTTP), not the
`--transport sse` currently in `Exec=`.

**`github-mcp-server` doesn't have this problem, and isn't Quadlet-managed
at all.** It only supports the `stdio` transport (confirmed against
upstream — no self-hosted HTTP/SSE mode exists; GitHub's own hosted
`api.githubcopilot.com` endpoint is unrelated). `home/bin/github-mcp-server-stdio`
is what actually runs it: an MCP client's stdio "command" points at that
script directly, which resolves the installed env files under
`~/.config/podrc/` and `exec`s `podman run -i --rm ...
ghcr.io/github/github-mcp-server:latest stdio` — one throwaway container
per connection. See README.md "Transport caveat" for the full rationale
and why `mcp-github.container` was removed rather than kept
`TODO(verify)` like the Kubernetes unit.

## Conventions

- Shell scripts: `set -euo pipefail`, resolve `SCRIPT_DIR`/`REPO_ROOT` via
  `BASH_SOURCE`, otherwise Google's Shell Style Guide
  (https://google.github.io/styleguide/shellguide.html) -- the Makefile
  itself still requires literal tabs for recipe lines, but that's a `make`
  syntax requirement, not a `hack/*.sh`/`home/bin/*` convention.
  Indentation is 2 spaces everywhere (Google's own guideline) --
  `hack/*.sh`, `home/bin/*`, `home/lib/podrc/*.sh`, and `test/` all follow
  the same convention; there's no more per-directory split.
- Every directly-run script in `hack/` puts its logic in functions and
  calls a `main "$@"` at the bottom; `hack/common.sh` is a library (only
  sourced) and has no `main`. `home/bin/*` scripts follow the same
  function/`main` shape but deliberately don't source `hack/common.sh` —
  they're installed and run standalone on a machine that may not have
  this repo checked out, and (for `github-mcp-server-stdio` specifically)
  can't risk `bash-logger`'s default stdout logging corrupting an MCP
  stdio stream.
- Global variables are kept to a minimum and marked `readonly` once
  assigned; anything more than the paths in `common.sh` should usually be a
  `local` inside a function instead.
- Status output uses `log_debug`/`log_info`/`log_warn`/`log_error` (from
  vendored `bash-logger`, via `init_logging()`) instead of `echo`. Plain
  `echo`/`cat` stays for actual function return values (e.g.
  `resolve_quadlet_bin`) and for human-facing instructional text not meant
  to look like a log line (e.g. `install.sh`'s "Next steps" block). This is
  a `hack/` convention only — `home/bin/*` scripts avoid the logger
  entirely (see above) and write diagnostics straight to stderr with `echo`.
- Quadlet units use `%h` for the invoking user's home directory
  (systemd specifier), not `$HOME`.
- The Kubernetes service publishes only to `127.0.0.1:8081` — never bind a
  published port to a wider interface without updating the README's
  "Ports" section too. The GitHub server publishes nothing; it has no
  Quadlet-managed container (see "Architecture" above).
