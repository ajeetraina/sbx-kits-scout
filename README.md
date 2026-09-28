# sbx-kit-docker-scout

A Docker Sandboxes kit (v3 format) that adds the **Docker Scout CLI** to any
agent sandbox. It is a mixin, so you layer it onto any agent: claude, codex,
copilot, opencode, or a plain shell.

## What it does

- Installs the `docker scout` CLI plugin into the system plugin directory
  `/usr/local/lib/docker/cli-plugins/docker-scout`, using the official Scout
  install script. The plugin is baked into the kit image at build time, so every
  sandbox has Scout the instant it starts, with no per-create download.
- Pins the version through a kit arg. `scoutVersion` defaults to `latest` and
  accepts a semver such as `1.18.3`.
- Opens only the network egress that sign-in and scanning need (the Scout API,
  Docker Hub, the Docker registry and its CDN, and dhi.io).
- Runs `docker scout version` on startup as a health check.

It does not ship credentials in environment variables. See
[Sign-in](#sign-in) for why, and for the one-time step.

## Requirements

`docker scout` is a docker CLI plugin, so it needs the **docker CLI on the base
image**. Use a docker-capable base such as the shell-docker template (the
built-in `shell` agent uses it). The kit does not declare docker as a hard
requirement on purpose: there is no universal package name for it across Debian,
Alpine, and template bases, and a hard requirement would make the kit refuse to
compose on bases that would in fact run the plugin. If docker is missing, the
startup check prints a clear message instead of failing.

## Run it locally

A v3 mixin must layer onto a v3 **workload** kit. The built-in `shell`/`claude`
agent names resolve to plain images, not v3 workloads, so composing directly
onto them fails with "no workload kit in the set." Use a published v3 workload
base such as `docker/sbx-kit-shell` (or `docker/sbx-kit-codex`,
`docker/sbx-kit-claude`, etc.):

```sh
# Layer the kit onto the v3 shell workload, in the current directory.
sbx run docker/sbx-kit-shell --kit . .

# Pin a specific Scout version.
sbx run docker/sbx-kit-shell --kit . --kit-arg scoutVersion=1.24.0 .

# Layer it onto a coding agent instead of the shell.
sbx run docker/sbx-kit-codex --kit . .
```

Inside the sandbox:

```sh
docker scout version
docker login                 # one time, see Sign-in below
docker scout cves registry://dhi.io/node:22-alpine3.24
```

## Run it in the cloud

Cloud sandboxes take the same flags:

```sh
sbx --cloud run docker/sbx-kit-shell --kit .
```

Or reference the kit by its published OCI tag once you have pushed it (see
[Publishing](#publishing)):

```sh
sbx --cloud run docker/sbx-kit-shell --kit docker.io/ajeetraina/sbx-kit-docker-scout:latest
```

## Sign-in

Scanning public images works with no sign-in. Private images, Docker Hardened
Images (dhi.io), and the full Scout API need a Docker account.

Scout authenticates by exchanging a Docker Hub personal access token (PAT) for a
short-lived JWT, then using that JWT against the registries and the Scout API.
That is a login handshake, not a fixed header, so the sandbox credential proxy
cannot perform it by injecting a header on outbound requests. For that reason
this kit deliberately does not accept a raw PAT in an environment variable,
which would also expose it to the agent process and to `env`. Sign in once
instead:

```sh
docker login          # Docker Hub: username + a PAT at the prompt
docker login dhi.io   # only if you scan dhi.io images
```

`docker login` writes the credential to `~/.docker/config.json` in the sandbox,
and Scout reads it from there. Because the PAT is typed at the interactive
prompt, it never lands in your shell history.

## Example commands

```sh
# Quick summary: packages, base image, vulnerability counts.
docker scout quickview node:22-alpine

# Full CVE list.
docker scout cves node:22-alpine

# Scan straight from a registry without pulling first.
docker scout cves registry://dhi.io/node:22-alpine3.24

# Compare a stock image against a Docker Hardened Image.
docker scout compare --to registry://dhi.io/node:22-alpine3.24 node:22-alpine
```

## Network allowlist

The kit allows only these hosts at runtime, and each is exercised by sign-in or
by a scan:

| Host | Why |
|---|---|
| `api.scout.docker.com` | Scout API: CVE enrichment, policy, recommendations |
| `hub.docker.com` | Docker Hub API |
| `auth.docker.io` | PAT to JWT token exchange for sign-in |
| `registry-1.docker.io` | Docker Hub registry (manifests, SBOM, config) |
| `production.cloudflare.docker.com` | Docker Hub blob CDN |
| `dhi.io` | Docker Hardened Images registry |

The install-time hosts (`raw.githubusercontent.com`, `github.com`,
`api.github.com`, and the GitHub release asset CDN) are reached by
`docker buildx build` when the kit image is built, not by the running sandbox,
so they are not in the runtime policy.

## How it is built

This is a v3 kit: a Dockerfile-based overlay built by the `docker/sandbox-kit:3`
BuildKit frontend.

- `sbx-kit-docker-scout.yaml` is the descriptor (capabilities, args, network
  policy, lifecycle, agent context).
- `sbx-kit-docker-scout.dockerfile` is the overlay recipe: it runs the official
  Scout install script in a build stage and copies the plugin into a `scratch`
  overlay.
- `scout-context.md` is the instruction file the agent reads.

Validate and build locally:

```sh
# Preview how the kit resolves.
sbx kit inspect .

# Build to an OCI layout and run the conformance suite.
docker buildx build . -f sbx-kit-docker-scout.yaml \
  -t sbx-kit-docker-scout:latest \
  --output type=oci,dest=/tmp/sbx-kit-docker-scout-layout,tar=false
kit-tck validate --layout /tmp/sbx-kit-docker-scout-layout latest
```

## Publishing

v3 kits are published as OCI images with `docker buildx build --push`, not with
`sbx kit push` (that verb is for the older schemaVersion 1 and 2 ZIP/tar kits).
Push both platforms in one build so the tag serves a proper multi-arch index:

```sh
docker buildx build . -f sbx-kit-docker-scout.yaml \
  --platform linux/amd64,linux/arm64 --push \
  -t docker.io/ajeetraina/sbx-kit-docker-scout:0.1.0 \
  -t docker.io/ajeetraina/sbx-kit-docker-scout:latest
```

To pin a specific Scout release into the published image, add
`--build-arg SCOUT_VERSION=1.24.0` (or use `--kit-arg scoutVersion=1.24.0` at
run time on an unpinned image).
