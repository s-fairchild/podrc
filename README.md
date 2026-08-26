# mcp-quadlets

[Podman Quadlet](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
files that run MCP (Model Context Protocol) servers as rootless, per-user
systemd services: a GitHub MCP server and a Kubernetes MCP server.

## Layout

`config/` mirrors the filesystem layout these files have once installed —
everything under it lands at the matching path under `$XDG_CONFIG_HOME`
(usually `~/.config`):

```
mcp-quadlets/
├── config/
│   └── containers/
│       └── systemd/            -> ~/.config/containers/systemd/
│           ├── mcp.network             shared podman network
│           ├── mcp-github.container    GitHub MCP server
│           └── mcp-kubernetes.container Kubernetes MCP server
├── env/                         -> ~/.config/mcp-quadlets/*.env (copied, not mirrored 1:1)
│   ├── mcp-github.env.example
│   └── mcp-kubernetes.env.example
├── scripts/                     lint/generate/install/uninstall, called by the Makefile
├── test/                        bats test suite for the Makefile targets
│   └── vendor/                  bats-core, bats-support, bats-assert (git submodules)
└── Makefile
```

`env/*.env.example` are templates. `make install` copies each to
`~/.config/mcp-quadlets/<name>.env` **only if that file doesn't already
exist**, so real secrets are never clobbered by a reinstall and never live
under `config/` (which is a straight filesystem mirror you might otherwise
be tempted to symlink wholesale).

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
                # binary (no real systemd paths touched) + shellcheck scripts/
make generate   # materialize the systemd units quadlet would produce into
                # .generated/, so you can eyeball the resulting ExecStart
make install    # lint, then copy units to ~/.config/containers/systemd,
                # write env templates to ~/.config/mcp-quadlets (skipping
                # any that already exist), daemon-reload, and enable
                # (but not start) both services
make uninstall  # stop, disable, and remove the installed units;
                # env files (secrets) are left in place
make uninstall-purge  # uninstall, and also delete the env files
make test       # run the bats suite against all of the above
```

`make lint` and `make generate` point the `quadlet` binary at this repo's
`config/containers/systemd/` via the `QUADLET_UNIT_DIRS` environment
variable it supports for exactly this purpose — they never read from or
write to your real `~/.config/containers/systemd`. Only `make install` /
`make uninstall` touch real paths, and only under `$XDG_CONFIG_HOME`.

### First real install

1. `make install`
2. Fill in real values in `~/.config/mcp-quadlets/mcp-github.env` and
   `mcp-kubernetes.env` (GitHub PAT, kubeconfig path, etc).
3. Resolve the `TODO(verify)` notes in both `.container` files — see
   "Transport caveat" below, this is not optional.
4. `systemctl --user start mcp-github.service mcp-kubernetes.service`
5. `loginctl enable-linger "$USER"` if you want these to keep running
   after you log out / restart without logging back in. This changes
   real system state (registers your user with `systemd-logind` for
   lingering) so it's a deliberate manual step, not something
   `make install` does for you.

## Transport caveat

MCP servers are usually spawned per-connection over stdio by the client
(`docker run -i ...`) — that model doesn't fit a long-lived systemd
service, which has no client attached to its stdin/stdout. Running one
as a Quadlet-managed service only makes sense if the server has a
persistent network transport (HTTP or SSE) you can point an MCP client
at via URL instead.

Both `.container` files here assume a `--transport sse --port <N>`-style
flag exists on the image in use, and both are marked `TODO(verify)`
because the exact flag/env var (and, for the Kubernetes server, which of
several same-named community images to run) depends on the specific
image version — check `podman run --rm <image> --help` before deploying.
Update `Image=` and `Exec=` in the relevant `.container` file to match
what you find, then re-run `make lint`.

## Ports

Both services publish to `127.0.0.1` only (`8081` for GitHub, `8082` for
Kubernetes) — not exposed off the host. Point your MCP client's SSE/HTTP
transport config at `http://127.0.0.1:8081` / `:8082`.
