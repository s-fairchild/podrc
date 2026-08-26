# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Podman Quadlet unit files that run two MCP (Model Context Protocol) servers
(GitHub, Kubernetes) as rootless, per-user systemd services, plus a
Makefile/scripts harness to lint, generate, install, and uninstall them. It
is a deployment/config repo, not an application — there is no application
source code to build or run, only unit files, shell scripts, and bats tests.

## Commands

```bash
git submodule update --init --recursive   # or: make submodules — required once after cloning

make lint             # shellcheck scripts/*.sh + dry-run every quadlet unit through
                       # the local `quadlet` binary (no real systemd paths touched)
make generate         # materialize the systemd units quadlet would produce into
                       # .generated/dryrun-output.txt, for inspecting ExecStart
make install          # lint, then copy units to ~/.config/containers/systemd,
                       # write env templates to ~/.config/mcp-quadlets, daemon-reload,
                       # enable (not start) both services
make uninstall        # stop, disable, remove installed units; env secrets kept
make uninstall-purge  # uninstall, and also delete the env files
make test             # fetch submodules if needed, then run the full bats suite
make clean            # remove .generated/
make distclean        # clean + deinit vendored submodules
```

Run a single test file or case directly with bats (skip the Makefile's
submodule check if already fetched):

```bash
test/vendor/bats-core/bin/bats test/install.bats
test/vendor/bats-core/bin/bats test/install.bats -f "never overwrites"
```

`quadlet` must be present at `/usr/libexec/podman/quadlet` or
`/usr/lib/podman/quadlet` (Fedora: part of the `podman` package) for
`lint`/`generate`/`test` to work; override with `QUADLET_BIN=/path/to/quadlet`.

## Architecture

**`config/` is a literal filesystem mirror.** Everything under
`config/containers/systemd/` lands at the identical relative path under
`$XDG_CONFIG_HOME` (usually `~/.config`) when installed. Don't add files
here that aren't meant to be installed verbatim.

**`env/*.example` is a separate, non-mirrored path** — despite the
directory's name, it holds both env-file and config-file templates (e.g.
`mcp-kubernetes.toml.example` alongside the `*.env.example` files).
`make install` copies each to `~/.config/mcp-quadlets/<name>` (stripping
only the `.example` suffix) *only if that destination doesn't already
exist*, so a reinstall never clobbers a filled-in secret or hand-edited
config. This is why these templates live outside `config/` instead of
being mirrored — a mirror would tempt clobbering real values on reinstall.

**The `-systemd.env` / `-systemd.env.example` suffix marks the `[Service]`
side of that split.** A plain `<name>.env(.example)` is referenced by
`EnvironmentFile=` in a unit's `[Container]` section — those values become
environment variables inside the running container. A
`<name>-systemd.env(.example)` is referenced by `EnvironmentFile=` in the
same unit's `[Service]` section instead — read by systemd itself, not
passed into the container — for values a unit needs outside the container,
e.g. a podman secret name interpolated into a `Secret=` line in
`[Container]`, or a value checked by an `ExecStartPre=` guard. All of
these files still land in the same `~/.config/mcp-quadlets/` directory on
install; only the suffix distinguishes which unit section reads them.

**A non-`.env` template (e.g. `mcp-kubernetes.toml.example`) is neither of
those** — it's not `EnvironmentFile=`'d in at all. It's bind-mounted
straight into the container by a `Volume=` line in the `.container` unit,
at the in-container path its sibling `-systemd.env` file points the
relevant flag (e.g. `CONFIG` → `--config`) at. `install_env_templates()`
in `scripts/install.sh` globs `*.example` generically (not `*.env.example`)
specifically so this kind of file gets picked up too — keep that in mind
if adding a new template that isn't a `.env` file.

**`scripts/common.sh`** is sourced (not executed) by every other script in
`scripts/`; it defines the readonly globals `SCRIPT_DIR`, `REPO_ROOT`,
`QUADLET_SRC_DIR`, `ENV_EXAMPLE_DIR`, and the functions `init_logging()`,
`resolve_quadlet_bin()`, `install_config_dir()`, `install_env_dir()`. New
scripts should source it the same way rather than recomputing these paths.

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
the local `quadlet` binary at this repo's `config/containers/systemd/` via
the `QUADLET_UNIT_DIRS` env var (which `quadlet` itself supports for this
purpose) and dry-run into a throwaway/`.generated` dir. Only `install.sh`
and `uninstall.sh` write to real paths, and only under `$XDG_CONFIG_HOME`
— never as root, never outside the user's own config.

**Test isolation (`test/test_helper.bash`)**: `setup_sandbox` redirects
`HOME`/`XDG_CONFIG_HOME` into a `mktemp -d` sandbox and prepends
`test/fixtures/bin/` (a fake `systemctl` that just logs its argv to
`SYSTEMCTL_STUB_LOG` instead of touching the real user systemd manager) onto
`PATH`. Any bats test exercising `install.sh`/`uninstall.sh` must call
`setup_sandbox` in `setup()` and `teardown_sandbox` in `teardown()`. Tests
override `QUADLET_SRC_DIR` to point at `test/fixtures/bad-quadlets/` to
exercise the lint-failure path without touching the real quadlet units.

**Test deps are git submodules** (`test/vendor/{bats-core,bats-support,bats-assert}`),
not vendored copies — `make test`/`make submodules` runs
`git submodule update --init --recursive` automatically if
`test/vendor/bats-core/bin/bats` isn't executable yet.

**Each `.container` unit's `Image=` points at a sibling `.image` unit**
(`github-mcp-server.image`, `kubernetes-mcp-server.image`), not a bare
registry reference — Quadlet resolves the `.image` suffix to that unit,
generates `<name>-image.service` to pull it, and auto-adds the
`Requires=`/`After=` dependency on the `.container`'s generated service.
The actual `podman pull`-equivalent image reference lives in the
`[Image]` section of the `.image` file, so change it there, not in the
`.container` file.

**The two `.container` units (and `kubernetes-mcp-server.image`) are
intentionally incomplete** (`TODO(verify)` comments in each): MCP servers
are normally spawned per-connection over stdio, which doesn't fit a
long-lived systemd unit. These units assume the container image supports
a persistent SSE/HTTP transport flag instead (`--transport sse --port
<N>`), but the exact flag and — for the Kubernetes server specifically —
which of several same-named community images to use, must be verified
against the real image's `--help` output before this is
production-usable. See README.md "Transport caveat" before changing
`Image=` (in the `.image` file) or `Exec=` (in the `.container` file).
README.md "Configuring each server" links each image's upstream repo and
lists which of its env vars/flags this repo currently sets vs. leaves at
defaults — check it before adding new keys to `env/*.env.example`, and
note it already flags that the Kubernetes server's real flag is `--port`
(Streamable HTTP), not the `--transport sse` currently in `Exec=`.

## Conventions

- Shell scripts: `set -euo pipefail`, resolve `SCRIPT_DIR`/`REPO_ROOT` via
  `BASH_SOURCE`, tabs for indentation (matches existing scripts and the
  Makefile).
- Every directly-run script (`scripts/*.sh`) puts its logic in functions and
  calls a `main "$@"` at the bottom; `scripts/common.sh` is a library (only
  sourced) and has no `main`.
- Global variables are kept to a minimum and marked `readonly` once
  assigned; anything more than the paths in `common.sh` should usually be a
  `local` inside a function instead.
- Status output uses `log_debug`/`log_info`/`log_warn`/`log_error` (from
  vendored `bash-logger`, via `init_logging()`) instead of `echo`. Plain
  `echo`/`cat` stays for actual function return values (e.g.
  `resolve_quadlet_bin`) and for human-facing instructional text not meant
  to look like a log line (e.g. `install.sh`'s "Next steps" block).
- Quadlet units use `%h` for the invoking user's home directory
  (systemd specifier), not `$HOME`.
- Both services publish only to `127.0.0.1` (8081 GitHub, 8082 Kubernetes)
  — never bind a published port to a wider interface without updating the
  README's "Ports" section too.
