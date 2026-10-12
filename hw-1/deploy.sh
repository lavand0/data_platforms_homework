#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

./scripts/00-check-access.sh
./scripts/01-prepare-nodes.sh
./scripts/02-install-hadoop.sh
./scripts/03-configure.sh
./scripts/04-start-cluster.sh
./scripts/05-check-cluster.sh
