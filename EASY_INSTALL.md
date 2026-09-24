# AI Value Flywheel — Easy Install (portfolio-only, least privilege)

This is the low-friction way to stand up the app for a customer. It keeps Lakebase
(unchanged) but turns **live UC discovery OFF**, which removes the one grant that
needs an **account admin**. The portfolio ships with 240 reference use cases, so the
app is fully useful on day one; you can feed the customer's real estate later via the
human-run extractor + Excel import.

## One command

```bash
PROFILE=<cli-profile> \
WAREHOUSE_ID=<sql-warehouse-id> \
GENIE_MIRROR_CATALOG=<catalog-the-app-may-own-a-schema-in> \
./deploy_customer.sh
```

This runs `scripts/deploy.py --target prod --discovery off …`, then issues the explicit
`databricks apps deploy grid-atlas` that the bundle step alone does not always create.

## Grants the easy profile needs (and ONLY these)

The app authenticates as its own **service principal (SP)**. Whoever runs the deploy (or
a catalog admin) needs to allow these. None require an *account* admin:

```sql
-- The app's OWN schema (for the optional Genie-assistant mirror). Least privilege.
GRANT USE CATALOG, CREATE SCHEMA ON CATALOG `<GENIE_MIRROR_CATALOG>` TO `<app-sp>`;
CREATE SCHEMA IF NOT EXISTS `<GENIE_MIRROR_CATALOG>`.`grid_atlas`;
GRANT USE SCHEMA, SELECT, MODIFY, CREATE TABLE
  ON SCHEMA `<GENIE_MIRROR_CATALOG>`.`grid_atlas` TO `<app-sp>`;
```

Plus, handled automatically by the bundle / deploy script:
- **Warehouse** `CAN_USE` (bundle resource binding).
- **Serving endpoint** `CAN_QUERY` (bundle resource binding).
- **Lakebase**: the SP's Postgres role + DML on `public` (deploy.py registers it;
  see the Lakebase note below).

### NOT needed in the easy profile

- `GRANT SELECT ON SCHEMA system.access TO <app-sp>;` — **account-admin only**. This is
  the discovery/lineage grant, skipped when `--discovery off`. If you later turn live
  discovery on, an account admin runs just this one statement.
- Any cross-catalog access. The easy profile grants the app **only its own schema**.

## Getting the customer's real data in (without broad grants)

Discovery is off, but you still get a full inventory — run it as a human, not the app:

1. Give the customer `schema-extractor/` (one Python file + `requirements.txt` +
   `workspaces.txt`). It runs under **their** creds, reads **UC metadata only** (no rows),
   across every workspace they can reach, and writes CSVs.
2. Upload those CSVs in the app under **Setup → Data Sources**.
3. Or skip data entirely and start from the 240 reference use cases + Excel import.

This is the recommended path even when discovery *could* be on: the app SP never needs
cross-catalog or `system.access` access, because the human's credentials do the reading.

## Lakebase note (why it is the way it is)

Drew's app connects to a Lakebase **project** over plain Postgres (PGHOST/PGUSER + a fresh
SP OAuth token), and deliberately does **not** bind a native `database` app-resource.
Binding a database *instance* creates a Postgres role that OAuth token auth then rejects
("External authorization failed"). The AICOE apps independently use the **same** pattern
and cite the same reasoning, so this is the correct approach, not extra complexity — it is
left unchanged in the easy profile.

## Turning discovery back on later

Run the normal installer with discovery on and supply a discovery catalog:

```bash
python3 scripts/deploy.py --target prod --discovery on \
  --profile <p> --warehouse-id <wh> --atlas-catalog <catalog> ...
```

An **account admin** then runs the single `system.access` grant above (the deploy prints it).
