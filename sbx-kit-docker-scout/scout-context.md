# Docker Scout CLI

The Docker Scout plugin is installed at
`/usr/local/lib/docker/cli-plugins/docker-scout`, so `docker scout` works out of
the box. It also runs directly as `docker-scout` if the docker CLI is absent.

## Sign-in

Scanning public images works without sign-in. Private images, Docker Hardened
Images (dhi.io), and the full Scout API need a Docker account.

Scout does not use a static token. It exchanges a Docker Hub personal access
token (PAT) for a short-lived JWT and then talks to the registries and the Scout
API with that JWT. That handshake is a login, not a header, so it cannot be done
by the sandbox credential proxy injecting a fixed header. This kit therefore
does not put a PAT in an environment variable. Sign in once instead:

```sh
# Docker Hub. Enter your username and a PAT (not your password) when prompted.
docker login

# Docker Hardened Images, if you scan dhi.io images.
docker login dhi.io
```

`docker login` stores the credential in `~/.docker/config.json` inside the
sandbox, and Scout reads it from there. The PAT is typed into the interactive
prompt, so it does not land in your shell history.

## Example commands

```sh
# One-line summary of an image: packages, layers, vulnerability counts.
docker scout quickview node:22-alpine

# Full CVE list for an image.
docker scout cves node:22-alpine

# Scan an image straight from a registry, without pulling it first.
docker scout cves registry://dhi.io/node:22-alpine3.24

# Compare a stock image against a Docker Hardened Image to see what hardening
# removes. Great for justifying a base-image swap.
docker scout compare --to registry://dhi.io/node:22-alpine3.24 node:22-alpine

# Show which policies an image passes or fails.
docker scout policy node:22-alpine

# Suggest less-vulnerable base images.
docker scout recommendations node:22-alpine
```

## Notes

- Do not print or paste your PAT. Use the `docker login` prompt.
- If `docker scout` reports it cannot find docker, the base image has no docker
  CLI. Use a docker-capable base such as the shell-docker template.
