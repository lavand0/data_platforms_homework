#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

./scripts/00-check-access.sh
./scripts/01-prepare-nodes.sh
./scripts/02-install-hadoop.sh
./scripts/03-configure.sh
./scripts/04-start-cluster.sh
./scripts/05-check-cluster.sh
./scripts/06-start-yarn.sh
./scripts/07-install-hive.sh
./scripts/08-start-hive.sh
./scripts/09-publish-web.sh
./scripts/10-check-yarn.sh
./scripts/11-load-data.sh
./scripts/12-check-hive.sh
