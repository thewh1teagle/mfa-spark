#!/usr/bin/env bash
set -euo pipefail

cd "${MFA_SPARK_ROOT:-/workspace}"
source ./scripts/env.sh
source ./.venv/bin/activate

if [[ "$#" -eq 0 ]]; then
  exec bash
fi

exec "$@"
