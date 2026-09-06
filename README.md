# mcpod

[Podman Quadlet](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
files that run MCP (Model Context Protocol) servers as rootless, per-user
systemd services: a GitHub MCP server and a Kubernetes MCP server.

## Layout

`home/` mirrors the filesystem layout these files have once installed —
everything under `home/config/` lands at the matching path under
`$XDG_CONFIG_HOME` (usually `~/.config`), everything under `home/bin/` at
the matching path under `~/.local/bin`, everything under `home/lib/` at
the matching path under `~/.local/lib/mcpod`. `hack/` is the
opposite: the lint/generate/install/uninstall harness that operates on
`home/`, never itself installed anywhere.

```
mcpod/
├── home/
│   ├── config/
│   │   └── containers/
│   │       └── systemd/            -> ~/.config/containers/systemd/
│   │           ├── mcp.network                    shared podman network
│   │           ├── github-mcp-server.image        GitHub MCP server image pull
│   │           ├── kubernetes-mcp-server.image    Kubernetes MCP server image pull
│   │           └── kubernetes-mcp-server.container  Kubernetes MCP server
│   ├── bin/                         -> ~/.local/bin/* (mode 0744)
│   │   ├── github-mcp-server-stdio                GitHub MCP server, spawned per-connection
│   │   ├── kubernetes-mcp-kubeconfig-secret       writes the kubeconfig podman secret
│   │   ├── busybox                                containerized busybox
│   │   ├── butane                                 containerized butane
│   │   ├── coreos-installer                       containerized coreos-installer
│   │   ├── ignition                               containerized ignition-validate
│   │   └── yq                                     containerized yq
│   └── lib/
│       └── mcpod/                   -> ~/.local/lib/mcpod/* (mode 0644, not executable)
│           (library code home/bin/ scripts source)
├── env/                              -> ~/.config/mcpod/* (copied recursively, not mirrored 1:1)
│   ├── github-mcp-server.env.example
│   ├── kubernetes-mcp.env.example
│   ├── kubernetes-mcp-systemd.env.example
│   ├── etc/
│   │   └── kubernetes-mcp-server/
│   │       ├── config.toml.example
│   │       └── conf.d/
│   │           ├── 00-base.toml.example
│   │           └── ...
│   └── environment.d/                -> ~/.config/environment.d/* (opt-in, see below)
│       └── mcpod.conf.example
├── hack/                             lint/generate/install/install-local/uninstall, called by the Makefile
├── test/                             bats test suite for the Makefile targets
│   └── vendor/                       bats-core, bats-support, bats-assert (git submodules)
└── Makefile
```

There's no `mcp-github.container` — `github-mcp-server` only supports the
`stdio` transport, which doesn't fit a long-lived systemd service; see
"Transport caveat" below.

`env/*.example` are templates — env files and, where a server takes one, a
config file (e.g. `etc/kubernetes-mcp-server/config.toml.example`). `make
install` copies every `*.example` file under `env/` (except
`env/environment.d/`, installed separately — see "Session-wide
XDG_CONFIG_HOME" below) into `~/.config/mcpod/`, recursively and
preserving the path relative to `env/`, dropping only the `.example`
suffix — e.g. `env/etc/kubernetes-mcp-server/conf.d/00-base.toml.example`
lands at `~/.config/mcpod/etc/kubernetes-mcp-server/conf.d/00-base.toml`.
This happens **only if that destination doesn't already exist**, so real
secrets or hand-edited config are never clobbered by a reinstall — edit
them in place under `~/.config/mcpod/` afterwards. None of it lives under
`home/config/` (which is a straight filesystem mirror you might otherwise
be tempted to symlink wholesale).

Files named `<name>.env.example` are referenced by `EnvironmentFile=` in
each unit's `[Container]` section — they become environment variables
*inside* the running container. Files named `<name>-systemd.env.example`
are referenced by `EnvironmentFile=` in the unit's `[Service]` section
instead — they're read by systemd itself before the container starts, and
are used for values that need to exist outside the container (e.g. a
podman secret name substituted into a `Secret=` line, or checked by an
`ExecStartPre=` guard). A file like `etc/kubernetes-mcp-server/config.toml.example`
is neither — it isn't `EnvironmentFile=`'d in, its installed directory is
bind-mounted by a `Volume=` line straight into the container at the path
`kubernetes-mcp-server.container`'s `Exec=` points `--config` at. All three kinds
land in the same `~/.config/mcpod/` directory on install, distinguished by
name/suffix.

## Prerequisites

- `podman` with the `quadlet` generator installed (Fedora: part of the
  `podman` package, binary at `/usr/libexec/podman/quadlet`)
- systemd user instance (`systemctl --user`) — normal on any modern
  systemd desktop/server distro
- `shellcheck` (optional but used by `make lint`)
- `kcov` (optional but used by `make coverage`; Fedora: `dnf install kcov`)
- `git` with submodule support, for the vendored test suite

After cloning:

```bash
git submodule update --init --recursive   # or: make submodules
```

## Usage

```bash
make lint       # dry-run every quadlet unit through the local `quadlet`
                # binary (no real systemd paths touched) + shellcheck
                # hack/*.sh, home/bin/*, home/lib/*
make generate   # materialize the systemd units quadlet would produce into
                # .generated/, so you can eyeball the resulting ExecStart
make install    # lint, then copy units to ~/.config/containers/systemd,
                # write env templates to ~/.config/mcpod (skipping
                # any that already exist), daemon-reload (quadlet
                # auto-enables via each unit's own [Install])
make install-local  # install home/bin/* to ~/.local/bin (0744) and
                     # home/lib/* to ~/.local/lib/mcpod (0644) --
                     # not systemd-managed, so separate from `make install`
make uninstall  # stop, disable, and remove the installed units;
                # env files (secrets) are left in place
make uninstall-purge  # uninstall, and also delete the env files and
                       # remove this repo's podman containers/networks
                       # (volumes and secrets are left alone)
make install-session-env    # opt-in: write the XDG_CONFIG_HOME
                             # environment.d template to
                             # ~/.config/environment.d (skipping it if it
                             # already exists) -- see "Session-wide
                             # XDG_CONFIG_HOME" below
make uninstall-session-env  # remove the template install-session-env wrote
make install-claude-mcp     # opt-in: register kubernetes-mcp and mcp-github
                             # with the local `claude` CLI's user-scope MCP
                             # config (skipping a name that's already
                             # registered) -- see "Registering with Claude
                             # Code" below
make uninstall-claude-mcp   # remove the registrations install-claude-mcp wrote
make test       # run the bats suite against all of the above
make coverage   # run the bats suite under kcov, report line coverage of
                # hack/*.sh and home/bin/* as HTML into .coverage/
```

`make lint` and `make generate` point the `quadlet` binary at this repo's
`home/config/containers/systemd/` via the `QUADLET_UNIT_DIRS` environment
variable it supports for exactly this purpose — they never read from or
write to your real `~/.config/containers/systemd`. Only `make install` /
`make uninstall` / `make install-local` / `make install-session-env` /
`make uninstall-session-env` touch real paths under `$XDG_CONFIG_HOME` /
`~/.local`; `make install-claude-mcp` / `make uninstall-claude-mcp` are the
one exception, touching the `claude` CLI's own user-scope config instead
(see "Registering with Claude Code" below).

### First real install

1. `make install`
2. Fill in real values in `~/.config/mcpod/github-mcp-server.env`
   (`GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`,
   `GITHUB_APP_PEM_PODMAN_SECRET`), `kubernetes-mcp.env`, and
   `kubernetes-mcp-systemd.env` (kubeconfig path, etc). Create the GitHub
   App private key's podman secret separately —
   `podman secret create github-app-private-key ./your-app.private-key.pem`
   — it's not written by `make install`. Create (or refresh) the
   Kubernetes kubeconfig secret with
   `~/.local/bin/kubernetes-mcp-kubeconfig-secret` (after
   `make install-local`) — it reads `~/.kube/config` and replaces the
   `KUBECONFIG_PODMAN_SECRET_NAME` secret, so re-run it whenever that
   kubeconfig changes. Edit
   `~/.config/mcpod/etc/kubernetes-mcp-server/{config.toml,conf.d/*.toml}`
   too if you need `--config`-driven settings; drop the matching
   `Volume=`/`--config` lines in `kubernetes-mcp-server.container` if you don't.
3. Resolve the `TODO(verify)` notes in `kubernetes-mcp-server.container` and
   `kubernetes-mcp-server.image` — see "Transport caveat" below, this is
   not optional.
4. `systemctl --user start kubernetes-mcp-server.service`
5. `loginctl enable-linger "$USER"` if you want that to keep running
   after you log out / restart without logging back in. This changes
   real system state (registers your user with `systemd-logind` for
   lingering) so it's a deliberate manual step, not something
   `make install` does for you.
6. `make install-local`, then point your MCP client's stdio server
   command at `~/.local/bin/github-mcp-server-stdio` (e.g.
   `claude mcp add mcp-github --scope user -- ~/.local/bin/github-mcp-server-stdio`
   for Claude Code). There's no systemd service to start for this one —
   see "Transport caveat".
7. For Claude Code specifically, `make install-claude-mcp` does step 6's
   `claude mcp add` for you, plus the equivalent `--transport http` add
   for `kubernetes-mcp` — see "Registering with Claude Code" below.

## Container-wrapped CLI tools

`home/bin/busybox`, `home/bin/butane`, `home/bin/coreos-installer`,
`home/bin/ignition`, and `home/bin/yq` aren't part of the MCP servers —
they're standalone convenience wrappers that run a container image
instead of requiring the real binary on the host, handy for building or
validating Fedora CoreOS/bootc artifacts (Butane configs, Ignition
configs, install media) alongside this repo. `make install-local`
installs them the same way as the MCP-related `home/bin/` scripts above.
Each one:

- runs `podman run --userns=keep-id --security-opt=label=disable` so the
  container sees the invoking user's UID/GID and SELinux label
  confinement doesn't block the bind mount
- bind-mounts `$PWD` at `/data` (`yq` mounts it read-write since `yq -i`
  edits files in place; the others mount it read-only) and sets it as
  `--workdir`
- forwards all of its own arguments straight to the containerized tool
- honors an optional `PODMAN_LOG_LEVEL` to set `podman run --log-level`

`yq` additionally forwards any `YQ_*`-prefixed environment variable into
the container (`--env=YQ_*`, for use in expressions via `env()`), and
always passes `--exit-status=1` so a false/null result exits non-zero,
matching the real `yq` binary's default behavior.

## Transport caveat

MCP servers are usually spawned per-connection over stdio by the client
(`docker run -i ...`) — that model doesn't fit a long-lived systemd
service, which has no client attached to its stdin/stdout. Running one
as a Quadlet-managed service only makes sense outright if the server has
a persistent network transport (HTTP or SSE) you can point an MCP client
at via URL instead.

`github-mcp-server` doesn't have one — `stdio` is the only local
transport it supports (its "remote"/HTTP mode is GitHub's own hosted
endpoint at `api.githubcopilot.com`, not something this image can serve
standalone), so there's no `mcp-github.container` in this repo at all.
Instead, `home/bin/github-mcp-server-stdio` is what an MCP client's stdio
"command" points at directly: it resolves the installed env files under
`~/.config/mcpod/` and `exec`s `podman run -i --rm ...
ghcr.io/github/github-mcp-server:latest stdio` — one throwaway container
per connection, never a resident service. `github-mcp-server.image` still
exists as a Quadlet unit purely to keep that image pulled/current
independent of that; nothing's `Image=` points at it.

`kubernetes-mcp-server.container` still assumes a `--transport sse --port <N>`-
style flag exists on the image in use, and is marked `TODO(verify)`
because the exact flag/env var (and which of several same-named
community images to run) depends on the specific image version — check
`podman run --rm <image> --help` before deploying. The image reference
itself lives in `kubernetes-mcp-server.image`; update `Image=` there and
`Exec=` in `kubernetes-mcp-server.container` to match what you find, then
re-run `make lint`.

## Session-wide XDG_CONFIG_HOME (optional)

Everything in this repo already falls back to `~/.config` on its own when
`XDG_CONFIG_HOME` is unset (`hack/common.sh`'s `install_env_dir()` and
friends, and the Quadlet units via `%h`), so there's nothing to configure
if that default is fine. If you *do* set `XDG_CONFIG_HOME` somewhere else,
setting it only in your shell's profile (`~/.bashrc`, `~/.bash_profile`)
covers interactive shells but not GUI apps, `systemctl --user` services,
or anything else started outside a login shell — they'd still see
`~/.config`.

`make install-session-env` covers that gap: it writes
`env/environment.d/mcpod.conf.example` to
`~/.config/environment.d/mcpod.conf` (skipping it if that destination
already exists, same skip-if-exists behavior as the `env/*.example`
templates `make install` writes). Uncomment its `XDG_CONFIG_HOME=` line
and edit the value, then log out and back in (or run
`systemctl --user daemon-reexec`) for systemd --user's environment.d
generator (`environment.d(5)`) to pick it up — at that point it applies
session-wide, not just to shells. `make uninstall-session-env` removes it
again. Neither target is part of `make install`/`make uninstall`, since
nothing else here depends on it.

## Configuring each server

The env files under `env/` (installed to `~/.config/mcpod/`) only
cover the settings this repo currently sets. Both servers accept more —
consult upstream for the full list before adding new keys.

### GitHub MCP server

`home/bin/github-mcp-server-stdio` / `github-mcp-server.image`. Upstream:
[github/github-mcp-server](https://github.com/github/github-mcp-server)
([README](https://github.com/github/github-mcp-server/blob/main/README.md)
documents all flags/env vars;
[`docs/remote-server.md`](https://github.com/github/github-mcp-server/blob/main/docs/remote-server.md)
covers the hosted remote variant, not relevant to this self-hosted setup).

Set by `github-mcp-server.env.example` in this repo, sourced directly by
`github-mcp-server-stdio` (not passed via `podman run --env-file=`). Auth
is via a GitHub App (see upstream
[`docs/github-app-auth.md`](https://github.com/github/github-mcp-server/blob/main/docs/github-app-auth.md)),
not a PAT:
- `GITHUB_APP_ID` / `GITHUB_APP_INSTALLATION_ID` — plain env, not secret
- `GITHUB_APP_PRIVATE_KEY_PATH` — path to the mounted PEM; set by the
  script itself to match the `target=` it computes for its `--secret`
  flag from `GITHUB_APP_PEM_PODMAN_SECRET` (e.g.
  `/run/secrets/github-app-private-key.key` for the default secret name)
- `GITHUB_APP_PEM_PODMAN_SECRET` — name of the podman secret holding the
  PEM contents, not the key material itself; create it yourself with
  `podman secret create github-app-private-key ./your-app.pem`,
  `make install` doesn't do this for you
- `GITHUB_TOOLSETS` — comma-separated toolsets to enable (equivalent to
  `--toolsets`)
- `GITHUB_READ_ONLY` — `1` disables all write tools

Other upstream env vars not currently set here, add to
`github-mcp-server.env.example` if needed: `GITHUB_HOST` (GitHub
Enterprise Server / GHE Cloud hostname), `GITHUB_TOOLS` (enable
individual tools instead of whole toolsets), `GITHUB_INSIDERS`
(experimental features).

### Kubernetes MCP server

`kubernetes-mcp-server.container` / `kubernetes-mcp-server.image`. The `.image`
file's `Image=` is a placeholder (`TODO(verify)`) — several unrelated
projects share this name. Upstream, assuming the intended one is
[containers/kubernetes-mcp-server](https://github.com/containers/kubernetes-mcp-server)
(Streamable-HTTP Kubernetes/OpenShift MCP server, matches the
`ghcr.io/containers/kubernetes-mcp-server` registry path already in the
`.image` file): confirm this is actually the image you're running before
trusting the flags below.

That project is flag/TOML-configured rather than env-var-driven:
`--port` (Streamable HTTP mode on path `/mcp` — note this is **not**
`--transport sse`, which is what `Exec=` in `kubernetes-mcp-server.container`
currently assumes; recheck this as part of that file's `TODO(verify)`),
`--kubeconfig` (path to kubeconfig — this repo instead mounts one via a
podman secret, see `kubernetes-mcp-systemd.env.example`), `--toolsets`,
`--read-only`, `--disable-destructive`, `--config` (TOML config file),
`--config-dir` (drop-in TOML directory). See the repo's README for the
complete flag/TOML reference.

`--config` is wired up in this repo via
`env/etc/kubernetes-mcp-server/config.toml.example` and
`conf.d/*.toml.example` (installed to
`~/.config/mcpod/etc/kubernetes-mcp-server/`, bind-mounted read-only as a
whole directory by the `Volume=` line in `kubernetes-mcp-server.container` at
`/etc/kubernetes-mcp-server`, the path `Exec=` points `--config` at).
Their keys are a best-effort mirror of the CLI flags and carry the same
`TODO(verify)` as everything else in this unit — confirm the real TOML
schema against the image before relying on it, and delete the
`Volume=`/`--config` lines plus the installed directory if you don't need
it.

## Registering with Claude Code

Once the servers are actually running (`kubernetes-mcp-server.service` started,
its `TODO(verify)` notes resolved — see "Transport caveat" — and/or
`make install-local` done for `github-mcp-server-stdio`), point the `claude` CLI
at them:

```bash
make install-claude-mcp    # registers both servers, skipping any name
                            # that's already registered
make uninstall-claude-mcp  # removes both registrations
```

This is equivalent to running, by hand:

```bash
claude mcp add --transport http kubernetes-mcp http://127.0.0.1:8081/mcp --scope user
claude mcp add mcp-github --scope user -- ~/.local/bin/github-mcp-server-stdio
```

Both are registered at `--scope user` (available in every project, not
project-local) since neither server is specific to this repo's checkout.
Requires the `claude` CLI on `PATH`; `mcp-github` is skipped with a
warning if `~/.local/bin/github-mcp-server-stdio` isn't installed yet
(`make install-local`). Neither target is part of `make install`/`make
uninstall` — see "Ports" below for why `kubernetes-mcp`'s URL has a
`/mcp` path, and "Configuring each server" for where that assumption
comes from.

## Ports

`github-mcp-server-stdio` runs `stdio` and publishes no port. The Kubernetes
service publishes to `127.0.0.1:8081` only — not exposed off the host.
Point your MCP client's HTTP transport config at
`http://127.0.0.1:8081/mcp` (Streamable HTTP on path `/mcp` — see
"Configuring each server"; `make install-claude-mcp` does this for
Claude Code automatically).
