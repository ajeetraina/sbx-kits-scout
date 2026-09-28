# syntax=docker/dockerfile:1

# Build stage: run the OFFICIAL Docker Scout install script and stage the plugin
# under /out, so the final overlay is just files that land on any base. The
# docker-scout plugin is a single static Go binary, so it travels in a scratch
# overlay with no shared-library closure and no dependency on the composed
# base's package manager. This is why the install happens here at build time
# rather than in a create-time hook: the plugin is baked into the kit, so every
# sandbox has it the instant it starts, with no per-create download.
#
# The builder is a Docker Hardened Image (dhi.io/debian-base:trixie-dev), the
# base the sandbox-kit-spec RECIPES.md recommends for a mixin overlay build
# stage. Nothing from it reaches the kit: the final stage is scratch and copies
# only the docker-scout binary, so the builder choice is about supply-chain
# hygiene of the build itself, not the shipped artifact. Because it is a DHI
# image, `docker buildx build` must be able to pull from dhi.io, so run
# `docker login dhi.io` first (or supply registry creds in CI).
ARG BUILDER_IMAGE=dhi.io/debian-base:trixie-dev
FROM ${BUILDER_IMAGE} AS build

# Wired to the scoutVersion kit arg via buildArg (see the descriptor).
ARG SCOUT_VERSION=latest

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    rm -rf /var/lib/apt/lists/*

# Install into the SYSTEM cli-plugins dir, staged under /out. This is the same
# official one-liner the project documents, just pointed at the staging root:
#   curl -fsSL .../install.sh | sh -s -- -b <dir> [tag]
# `latest` (the default) installs the newest release; a semver pins it. The
# release tags are v-prefixed, so 1.18.3 is normalized to v1.18.3.
RUN set -eux; \
    dir=/out/usr/local/lib/docker/cli-plugins; \
    mkdir -p "$dir"; \
    tag=""; \
    if [ "$SCOUT_VERSION" != latest ]; then \
      case "$SCOUT_VERSION" in \
        v*) tag="$SCOUT_VERSION" ;; \
        *)  tag="v$SCOUT_VERSION" ;; \
      esac; \
    fi; \
    curl -fsSL https://raw.githubusercontent.com/docker/scout-cli/main/install.sh \
      | sh -s -- -b "$dir" $tag; \
    # A pinned version is a claim about content, so make the build enforce it:
    # prove the binary runs, and when a version was requested prove it is the
    # one that got installed.
    "$dir/docker-scout" version; \
    if [ "$SCOUT_VERSION" != latest ]; then \
      "$dir/docker-scout" version 2>&1 | grep -q "${SCOUT_VERSION#v}"; \
    fi; \
    # scratch has no /etc/passwd, so normalize to numeric root ownership. The
    # plugin is a system binary the agent only needs to execute, not own.
    chown -R 0:0 /out; \
    chmod 0755 "$dir/docker-scout"

# The overlay: the docker-scout plugin only. It ships nothing under /home, so
# there are no home-ownership concerns, and it sets no ENTRYPOINT/USER/WORKDIR
# because a mixin cannot own those (the workload does).
FROM scratch
COPY --from=build /out /
