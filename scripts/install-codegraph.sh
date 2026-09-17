#!/bin/bash
# CodeGraph (@colbymchenry/codegraph) — pre-indexed code knowledge graph (local SQLite) that lets
# AI agents answer architecture questions in one call. npm global with prebuilt platform binaries
# (no native build). Installed into the base's user-owned /opt/npm prefix so it self-updates as the
# container user; re-chown after the root-run install, exactly like the base image does (see
# base/Containerfile — "Own the whole npm prefix as the container user").
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

npm install -g @colbymchenry/codegraph
chown -R ubuntu:ubuntu /opt/npm
