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
│   │           └── mcp-kubernetes.container       Kubernetes MCP server
│   ├── bin/                         -> ~/.local/bin/* (mode 0744)
│   │   └── mcp-github-stdio.sh                    GitHub MCP server, spawned per-connection
│   └── lib/                         -> ~/.local/lib/mcpod/* (mode 0644, not executable)
│       (empty for now -- for library code home/bin/ scripts source)
├── env/                              -> ~/.config/mcpod/* (copied, not mirrored 1:1)
│   ├── mcp-github.env.example
│   ├── mcp-github-systemd.env.example
│   ├── mcp-kubernetes.env.example
│   ├── mcp-kubernetes-systemd.env.example
│   └── mcp-kubernetes.toml.example
├── hack/                             lint/generate/install/install-local/uninstall, called by the Makefile
├── test/                             bats test suite for the Makefile targets
│   └── vendor/                       bats-core, bats-support, bats-assert (git submodules)
└── Makefile
```

There's no `mcp-github.container` — `github-mcp-server` only supports the
`stdio` transport, which doesn't fit a long-lived systemd service; see
"Transport caveat" below.

`env/*.example` are templates — env files and, where a server takes one, a
config file (e.g. `mcp-kubernetes.toml.example`). `make install` copies
each to `~/.config/mcpod/<name>` (dropping the `.example` suffix)
**only if that destination doesn't already exist**, so real secrets or
hand-edited config are never clobbered by a reinstall, and none of it
lives under `home/config/` (which is a straight filesystem mirror you
might otherwise be tempted to symlink wholesale).

Files named `<name>.env.example` are referenced by `EnvironmentFile=` in
each unit's `[Container]` section — they become environment variables
*inside* the running container. Files named `<name>-systemd.env.example`
are referenced by `EnvironmentFile=` in the unit's `[Service]` section
instead — they're read by systemd itself before the container starts, and
are used for values that need to exist outside the container (e.g. a
podman secret name substituted into a `Secret=` line, or checked by an
`ExecStartPre=` guard). A file like `mcp-kubernetes.toml.example` is
neither — it isn't `EnvironmentFile=`'d in, it's bind-mounted by a
`Volume=` line straight into the container at the path its own
`-systemd.env` file points `--config` at. All three kinds land in the
same `~/.config/mcpod/` directory on install, distinguished by
name/suffix.

## Prerequisites

- `podman` with the `quadlet` generator installed (Fedora: part of the
  `podman` package, binary at `/usr/libexec/podman/quadlet`)
- systemd user instance (`systemctl --user`) — normal on any modern
  systemd desktop/server distro
- `shellcheck` (optional but used by `make lint`)
- `git` with submodule support, for the vendored test suite

After cloning:

```bash
git submodule update --init --recursive   # or: make submodules
```

## Usage

```bash
make lint       # dry-run every quadlet unit through the local `quadlet`
                # binary (no real systemd paths touched) + shellcheck
                # hack/*.sh, home/bin/*.sh, home/lib/*.sh
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
make test       # run the bats suite against all of the above
```

`make lint` and `make generate` point the `quadlet` binary at this repo's
`home/config/containers/systemd/` via the `QUADLET_UNIT_DIRS` environment
variable it supports for exactly this purpose — they never read from or
write to your real `~/.config/containers/systemd`. Only `make install` /
`make uninstall` / `make install-local` touch real paths, and only under
`$XDG_CONFIG_HOME` / `~/.local`.

### First real install

1. `make install`
2. Fill in real values in `~/.config/mcpod/mcp-github.env`
   (`GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`), `mcp-github-systemd.env`
   (`GITHUB_APP_PRIVATE_KEY_PODMAN_SECRET`), `mcp-kubernetes.env`, and
   `mcp-kubernetes-systemd.env` (kubeconfig path, etc). Create the GitHub
   App private key's podman secret separately —
   `podman secret create github-app-private-key ./your-app.private-key.pem`
   — it's not written by `make install`. Edit `mcp-kubernetes.toml` too if
   you need `--config`-driven settings; clear `CONFIG` in
   `mcp-kubernetes-systemd.env` and drop the matching `Volume=`/`--config`
   lines in `mcp-kubernetes.container` if you don't.
3. Resolve the `TODO(verify)` notes in `mcp-kubernetes.container` and
   `kubernetes-mcp-server.image` — see "Transport caveat" below, this is
   not optional.
4. `systemctl --user start mcp-kubernetes.service`
5. `loginctl enable-linger "$USER"` if you want that to keep running
   after you log out / restart without logging back in. This changes
   real system state (registers your user with `systemd-logind` for
   lingering) so it's a deliberate manual step, not something
   `make install` does for you.
6. `make install-local`, then point your MCP client's stdio server
   command at `~/.local/bin/mcp-github-stdio.sh` (e.g.
   `claude mcp add mcp-github --scope user -- ~/.local/bin/mcp-github-stdio.sh`
   for Claude Code). There's no systemd service to start for this one —
   see "Transport caveat".

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
Instead, `home/bin/mcp-github-stdio.sh` is what an MCP client's stdio
"command" points at directly: it resolves the installed env files under
`~/.config/mcpod/` and `exec`s `podman run -i --rm ...
ghcr.io/github/github-mcp-server:latest stdio` — one throwaway container
per connection, never a resident service. `github-mcp-server.image` still
exists as a Quadlet unit purely to keep that image pulled/current
independent of that; nothing's `Image=` points at it.

`mcp-kubernetes.container` still assumes a `--transport sse --port <N>`-
style flag exists on the image in use, and is marked `TODO(verify)`
because the exact flag/env var (and which of several same-named
community images to run) depends on the specific image version — check
`podman run --rm <image> --help` before deploying. The image reference
itself lives in `kubernetes-mcp-server.image`; update `Image=` there and
`Exec=` in `mcp-kubernetes.container` to match what you find, then
re-run `make lint`.

## Configuring each server

The env files under `env/` (installed to `~/.config/mcpod/`) only
cover the settings this repo currently sets. Both servers accept more —
consult upstream for the full list before adding new keys.

### GitHub MCP server

`home/bin/mcp-github-stdio.sh` / `github-mcp-server.image`. Upstream:
[github/github-mcp-server](https://github.com/github/github-mcp-server)
([README](https://github.com/github/github-mcp-server/blob/main/README.md)
documents all flags/env vars;
[`docs/remote-server.md`](https://github.com/github/github-mcp-server/blob/main/docs/remote-server.md)
covers the hosted remote variant, not relevant to this self-hosted setup).

Set by `mcp-github.env.example` / `mcp-github-systemd.env.example` in this
repo. Auth is via a GitHub App (see upstream
[`docs/github-app-auth.md`](https://github.com/github/github-mcp-server/blob/main/docs/github-app-auth.md)),
not a PAT:
- `GITHUB_APP_ID` / `GITHUB_APP_INSTALLATION_ID` — plain env, not secret
- `GITHUB_APP_PRIVATE_KEY_PATH` — path to the mounted PEM, must match the
  `target=` in `mcp-github-stdio.sh`'s `--secret` flag
  (`/run/secrets/github-app-key.pem`)
- `GITHUB_APP_PRIVATE_KEY_PODMAN_SECRET` (in `mcp-github-systemd.env`) —
  name of the podman secret holding the PEM contents; create it yourself
  with `podman secret create github-app-private-key ./your-app.pem`,
  `make install` doesn't do this for you
- `GITHUB_TOOLSETS` — comma-separated toolsets to enable (equivalent to
  `--toolsets`)
- `GITHUB_READ_ONLY` — `1` disables all write tools

Other upstream env vars not currently set here, add to
`mcp-github.env.example` if needed: `GITHUB_HOST` (GitHub Enterprise
Server / GHE Cloud hostname), `GITHUB_TOOLS` (enable individual tools
instead of whole toolsets), `GITHUB_INSIDERS` (experimental features).

### Kubernetes MCP server

`mcp-kubernetes.container` / `kubernetes-mcp-server.image`. The `.image`
file's `Image=` is a placeholder (`TODO(verify)`) — several unrelated
projects share this name. Upstream, assuming the intended one is
[containers/kubernetes-mcp-server](https://github.com/containers/kubernetes-mcp-server)
(Streamable-HTTP Kubernetes/OpenShift MCP server, matches the
`ghcr.io/containers/kubernetes-mcp-server` registry path already in the
`.image` file): confirm this is actually the image you're running before
trusting the flags below.

That project is flag/TOML-configured rather than env-var-driven:
`--port` (Streamable HTTP mode on path `/mcp` — note this is **not**
`--transport sse`, which is what `Exec=` in `mcp-kubernetes.container`
currently assumes; recheck this as part of that file's `TODO(verify)`),
`--kubeconfig` (path to kubeconfig — this repo instead mounts one via a
podman secret, see `mcp-kubernetes-systemd.env.example`), `--toolsets`,
`--read-only`, `--disable-destructive`, `--config` (TOML config file),
`--config-dir` (drop-in TOML directory). See the repo's README for the
complete flag/TOML reference.

`--config` is wired up in this repo via `mcp-kubernetes.toml.example`
(installed to `~/.config/mcpod/mcp-kubernetes.toml`, bind-mounted
read-only by the `Volume=` line in `mcp-kubernetes.container` at the path
`CONFIG` names in `mcp-kubernetes-systemd.env`). Its keys are a
best-effort mirror of the CLI flags and carry the same `TODO(verify)` as
everything else in this unit — confirm the real TOML schema against the
image before relying on it, and delete the `Volume=`/`--config` lines
plus the installed `.toml` if you don't need it.

## Ports

`mcp-github-stdio.sh` runs `stdio` and publishes no port. The Kubernetes
service publishes to `127.0.0.1:8082` only — not exposed off the host.
Point your MCP client's HTTP transport config at `http://127.0.0.1:8082`.
