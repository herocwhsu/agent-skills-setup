# Migration: robots → atelier + hangar

**Status:** Planning  
**Updated:** 2026-06-25 after reading both repos  
**Repos:** `~/projects/atelier` (apps), `~/projects/hangar` (platform infra)

---

## Current state of k3s

```
robots-prod         robots-backend, robots-frontend (×2), cloudflared (×2), cron jobs
robots-monitoring   prometheus, grafana, alertmanager, node-exporter
```

No platform namespaces exist yet. Everything in the new stack needs to be provisioned from scratch.

---

## What changes

| Aspect | robots (current) | atelier+hangar (target) |
|---|---|---|
| DB | SQLite in pod | PostgreSQL (`platform-postgres` ns) |
| Cache | None | Redis (`platform-redis` ns) |
| Messaging | None | NATS (`platform-nats` ns) |
| News pipeline | supercronic cron in pod | k8s CronJob (missing — see below) → NATS → consumer pod |
| Registry | ad-hoc | Harbor (`platform-harbor` ns) |
| Secrets | manual k8s Secret | Vault → External Secrets Operator |
| Cloudflared | in `robots-prod` | in `network` ns (hangar-managed) |
| Observability | prometheus+grafana in `robots-monitoring` | loki+prometheus+grafana in hangar platform |
| CI/CD | manual kubectl | GitHub Actions → Harbor → kubectl apply |

---

## Order of operations

### Step 1 — Deploy platform namespaces

```bash
cd ~/projects/hangar
kubectl apply -f cluster/namespaces.yaml
```

Creates: `platform-postgres`, `platform-redis`, `platform-nats`, `platform-minio`,
`platform-harbor`, `platform-loki`, `platform-prometheus`, `platform-grafana`,
`platform-vault`, `platform-authentik`, `platform-external-secrets`, `platform-ntfy`, `network`

### Step 2 — Deploy Vault + ESO

```bash
kubectl apply -k services/vault/overlays/prod/
kubectl apply -k services/external-secrets/overlays/prod/
```

### Step 3 — Initialize Vault (once only)

```bash
./services/vault/policies/init-vault.sh
# Save unseal keys + root token from /tmp/vault-init.json → store securely, then delete
```

### Step 4 — Seed platform secrets into Vault

```bash
export VAULT_ADDR=http://vault.platform-vault.svc.cluster.local:8200
export VAULT_TOKEN=<ROOT_TOKEN>

vault kv put secret/platform/postgres \
  POSTGRES_USER=postgres POSTGRES_PASSWORD=<value> POSTGRES_DB=postgres

vault kv put secret/platform/harbor \
  HARBOR_ADMIN_PASSWORD=<value> DB_PASSWORD=<value> REDIS_PASSWORD=<value> \
  SECRET_KEY=<value> MINIO_ACCESS_KEY=<value> MINIO_SECRET_KEY=<value> \
  OIDC_CLIENT_SECRET=<value>

vault kv put secret/platform/minio \
  MINIO_ROOT_USER=minioadmin MINIO_ROOT_PASSWORD=<value>

vault kv put secret/platform/grafana \
  GRAFANA_ADMIN_PASSWORD=<value> GRAFANA_OIDC_CLIENT_SECRET=<value>

vault kv put secret/platform/ntfy \
  alertmanager_token=<value>

vault kv put secret/platform/authentik \
  AUTHENTIK_SECRET_KEY=<value> AUTHENTIK_POSTGRESQL_PASSWORD=<value>

vault kv put secret/platform/cloudflared \
  CLOUDFLARE_TUNNEL_TOKEN=<value>   # same token currently in robots-prod cloudflared
```

### Step 5 — Deploy platform services (in order)

```bash
# Data services first
kubectl apply -k services/postgres/overlays/prod/
kubectl apply -k services/redis/overlays/prod/
kubectl apply -k services/nats/overlays/prod/
kubectl apply -k services/minio/overlays/prod/

# Registry (Harbor)
kubectl apply -k services/harbor/overlays/prod/

# Observability
kubectl apply -k services/loki/overlays/prod/
kubectl apply -k services/prometheus/overlays/prod/
kubectl apply -k services/grafana/overlays/prod/
kubectl apply -k services/ntfy/overlays/prod/

# Identity
kubectl apply -k services/authentik/overlays/prod/

# Network (replaces robots-prod cloudflared)
kubectl apply -k network/traefik/overlays/prod/
kubectl apply -k network/cloudflared/overlays/prod/
```

### Step 6 — Onboard firstdigital app (one command)

```bash
export VAULT_TOKEN=<ROOT_TOKEN>
ansible-playbook ansible/onboard-app.yml -e app=firstdigital
```

This provisions: Postgres DB + user, Redis ACL, MinIO bucket, NATS account,
Vault policy + k8s auth role, Harbor project, Authentik group, Grafana folder,
k8s namespace `firstdigital`, ServiceAccount `firstdigital-sa`.

Output checklist written to `docs/apps/firstdigital.md`.

### Step 7 — Add app-specific secrets to Vault

```bash
vault kv patch secret/firstdigital/config \
  OPENROUTER_API_KEY=<value> \
  LLM_NEWS_MODEL=meta-llama/llama-3.2-3b-instruct:free \
  SECRET_KEY=<value>
```

### Step 8 — Data migration: SQLite → PostgreSQL

```bash
# Export from running robots pod
kubectl exec -n robots-prod <backend-pod> -- python3 -c "
import sqlite3, json, sys
conn = sqlite3.connect('/data/stock_data.db')
conn.row_factory = sqlite3.Row
for table in ['stock_prices','cape','cape_details','buffett','buffett_details','generated_insights','news_articles']:
    rows = conn.execute(f'SELECT * FROM {table}').fetchall()
    for row in rows:
        print(json.dumps({'table': table, 'row': dict(row)}))
" > /tmp/robots_export.jsonl

# Run SQL migrations on new Postgres
kubectl exec -n platform-postgres sts/postgres -- \
  psql -U firstdigital_user -d firstdigital < apps/firstdigital-api/src/infra/migrations/001_initial.sql
# repeat for 004, 005, 006

# Import rows (write a small Python script reading the jsonl and doing asyncpg inserts)
```

**Note:** `news_articles` is most valuable (833+ rows). CAPE data only through
2026-03-01 (upstream Yale/Shiller lag) — safe to re-fetch after migration.

### Step 9 — Add missing CronJob manifest

atelier has the NATS consumer pod (`deployment-news-consumer.yaml`) but nothing triggers the daily fetch. Need to add:

```
apps/firstdigital-api/deploy/k8s/base/cronjob-news-fetch.yaml
```

Then add it to `base/kustomization.yaml` resources. Schedule matches current supercronic:
- `0 9 * * *` — fetch (publishes `firstdigital.news.fetched` → consumer classifies)

The old separate `classify` cron job is replaced by the event-driven consumer pod.

### Step 10 — Build and push images to Harbor

CI does this automatically on merge to `main`. For first deploy (before CI is wired):

```bash
cd ~/projects/atelier

# API
docker build -t <HARBOR_REGISTRY>/firstdigital/api:latest apps/firstdigital-api/
docker push <HARBOR_REGISTRY>/firstdigital/api:latest

# Frontend
docker build -t <HARBOR_REGISTRY>/firstdigital/frontend:latest apps/firstdigital/
docker push <HARBOR_REGISTRY>/firstdigital/frontend:latest
```

### Step 11 — Deploy atelier apps

```bash
cd ~/projects/atelier

# Runs: DB migration Job + API deployment + news-consumer deployment
kubectl apply -k apps/firstdigital-api/deploy/k8s/overlays/prod/
kubectl rollout status deployment/firstdigital-api -n firstdigital

kubectl apply -k apps/firstdigital/deploy/k8s/overlays/prod/
kubectl rollout status deployment/firstdigital -n firstdigital
```

### Step 12 — Wire CI/CD

Add GitHub secrets to `herocwhsu/atelier`:

| Secret | Value |
|---|---|
| `HARBOR_REGISTRY` | Harbor hostname |
| `HARBOR_USERNAME` | Harbor robot account |
| `HARBOR_PASSWORD` | Harbor robot account password |
| `KUBECONFIG_B64` | `base64 < ~/.kube/config` |

After this, every merge to `main` auto-deploys.

### Step 13 — Cutover

1. Verify all checks: health endpoint, news flowing, charts loading, Grafana dashboards
2. Delete robots cloudflared (hangar's cloudflared now handles traffic):
   ```bash
   kubectl delete deployment cloudflared -n robots-prod
   ```
3. Scale robots to 0:
   ```bash
   kubectl scale deployment robots-backend robots-frontend -n robots-prod --replicas=0
   ```
4. Keep `robots-prod` namespace + SQLite data for 2 weeks as rollback
5. After 2 weeks: `kubectl delete namespace robots-prod robots-monitoring`

---

## Missing pieces (action items)

| Item | Location | Notes |
|---|---|---|
| CronJob for news-fetch | atelier `apps/firstdigital-api/deploy/k8s/base/` | Needs to be added |
| Data migration script | one-off | SQLite export → PostgreSQL import |
| GitHub secrets | `herocwhsu/atelier` repo settings | For CI/CD to trigger |
| Vault unseal keys | secure storage | Generated during Step 3 |

---

## Known issues from hangar backlog

See `~/projects/hangar/docs/backlog-2026-06-25.md` for full detail:

- **NATS core → JetStream** (B.8): current pub/sub is at-most-once — if consumer is down during fetch, event is lost. JetStream gives at-least-once. Spec-gated change, do after initial cutover.
- **Loki schema v11 → v13** (C.9): before first Loki upgrade
- **Redis readiness probe** (C.10): tcpSocket only, doesn't catch ACL misconfig
- **Migration numbering gap** (D.12): 002/003 missing — document or renumber
- **`date` columns as TEXT** (D.13): fragile; consider typed migration

---

## Backlog items to port from robots

See `docs/backlog.md`:
- **Evaluator-optimizer on news classify** — confidence-check LLM pass after classify, fits naturally into NATS consumer pipeline
- **Routing** — classify API query type, route to correct data source
