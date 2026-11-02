#!/usr/bin/env bash
# AI Value Flywheel — customer "easy install" deploy.
#
# Prod target + discovery OFF (portfolio-only, least privilege). This profile:
#   - deploys to the `prod` bundle target (no [dev] markers),
#   - turns OFF live UC discovery, so the account-admin `GRANT SELECT ON system.access`
#     is NOT issued (the portfolio ships with 240 reference use cases; feed your own
#     estate later via the human-run schema-extractor/ + Excel import),
#   - keeps Lakebase (unchanged from Drew's design — see EASY_INSTALL.md),
#   - fixes the two known deploy gaps: the app keeps one name on every target
#     (APP_NAME, default `grid-atlas`), and an explicit `databricks apps deploy` is
#     issued after the bundle upload (which `bundle run` alone does not always create).
#
# Usage:
#   PROFILE=<cli-profile> WAREHOUSE_ID=<sql-warehouse-id> \
#   GENIE_MIRROR_CATALOG=<catalog-the-app-may-own-a-schema-in> \
#   ./deploy_customer.sh
#
# Optional: APP_NAME (default grid-atlas), LAKEBASE_PROJECT (default grid-atlas-db),
# GENIE_MIRROR_SCHEMA (default grid_atlas). Change all three to install a second copy
# in a workspace that already has one.
set -euo pipefail
cd "$(dirname "$0")"

PROFILE="${PROFILE:-}"
APP_NAME="${APP_NAME:-grid-atlas}"
WAREHOUSE_ID="${WAREHOUSE_ID:-}"
GENIE_MIRROR_CATALOG="${GENIE_MIRROR_CATALOG:-}"
GENIE_MIRROR_SCHEMA="${GENIE_MIRROR_SCHEMA:-grid_atlas}"
SERVING_ENDPOINT="${SERVING_ENDPOINT:-databricks-claude-sonnet-5}"
LAKEBASE_PROJECT="${LAKEBASE_PROJECT:-grid-atlas-db}"
PG_DATABASE="${PG_DATABASE:-app}"

if [[ -z "$PROFILE" || -z "$WAREHOUSE_ID" || -z "$GENIE_MIRROR_CATALOG" ]]; then
  echo "Required: PROFILE, WAREHOUSE_ID, GENIE_MIRROR_CATALOG"
  echo "  PROFILE=myprofile WAREHOUSE_ID=abc123 GENIE_MIRROR_CATALOG=my_catalog ./deploy_customer.sh"
  echo "  (GENIE_MIRROR_CATALOG = a catalog where the app SP may own its own schema;"
  echo "   this is the app's OWN least-privilege schema, not broad access.)"
  exit 1
fi

echo ">> Step 1/2: deploy.py (target=prod, discovery=off)"
python3 scripts/deploy.py \
  --target prod \
  --discovery off \
  --profile "$PROFILE" \
  --warehouse-id "$WAREHOUSE_ID" \
  --atlas-catalog "" \
  --serving-endpoint "$SERVING_ENDPOINT" \
  --genie-mirror-catalog "$GENIE_MIRROR_CATALOG" \
  --genie-mirror-schema "$GENIE_MIRROR_SCHEMA" \
  --lakebase-project "$LAKEBASE_PROJECT" \
  --pg-database "$PG_DATABASE" \
  --app-name "$APP_NAME" \
  --yes

# `bundle run` uploads source but does not reliably create an app deployment.
# Trigger one explicitly against the prod bundle's uploaded files.
ME="$(databricks current-user me -p "$PROFILE" -o json \
      | python3 -c 'import sys,json;print(json.load(sys.stdin)["userName"])')"
SRC="/Workspace/Users/${ME}/.bundle/${APP_NAME}/prod/files"
echo ">> Step 2/2: databricks apps deploy ${APP_NAME} (source: $SRC)"
databricks apps deploy "$APP_NAME" --source-code-path "$SRC" -p "$PROFILE"

echo ">> Done. Open the app and visit Setup to confirm every dependency is green."
echo "   (Discovery is off; it will show as not-configured, which is expected.)"
