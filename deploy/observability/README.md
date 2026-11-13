# Observability

Metrics, traces, logs, dashboards and alerts for the API on the single-node k3s deployment
(`deploy/k8s`). Design and reasoning: issue #164.

```
 web pod (Rails)                     namespace: observability
  ├─ OTel metrics ─┐                 ┌───────────────────────────────────────────────┐
  ├─ OTel traces ──┼─ OTLP/HTTP ────▶│ otel-collector ─ metrics ▶ :8889 ◀─ Prometheus │◀─ Grafana
  └─ logs (stdout) ┘ /var/log/pods ─▶│      (DaemonSet) ─ traces ▶ Tempo              │   (alerts →
                                     │                  ─ logs ──▶ Loki               │    Telegram)
                                     │ Prometheus also scrapes Traefik, kubelet,      │
                                     │ node-exporter, kube-state-metrics, postgres-exp│
                                     └───────────────────────────────────────────────┘
 Outside the node: uptime probe on /up, healthchecks.io pinged by the reminders CronJob.
```

| Component | How | Memory (request / limit) | Keeps |
|---|---|---|---|
| OpenTelemetry Collector | `otel-collector.yaml`, config in `otel-collector/config.yaml` | 128Mi / 512Mi | — |
| Prometheus + node-exporter + kube-state-metrics | `prometheus.yaml` (HelmChart) | ~560Mi / ~2.1Gi | 15 days, ≤ 4GB |
| Grafana | `grafana.yaml` (HelmChart) | 256Mi / 1Gi | dashboards and alerts come from git |
| Tempo | `tempo.yaml` (HelmChart) | 256Mi / 1Gi | 72 hours |
| Loki | `loki.yaml` (HelmChart) | 256Mi / 1Gi | 7 days |
| postgres-exporter | `postgres-exporter.yaml` | 24Mi / 64Mi | — |

**Capacity.** That's ~1.5Gi requested and ~5.5Gi in limits on top of k3s, the app and Postgres, sized
for the 30 GB home server (2026-11-08). The earlier 256–400Mi limits got Grafana OOM-killed as soon as
the UI was used. On a small node (2–4 GB) lower them again, or skip `tempo.yaml` and `loki.yaml`: the
metrics, dashboards and alerts work without them.

## Install

On the server, in this order.

**1. Secrets** (never committed):

```bash
kubectl create namespace observability

# A read-only role for postgres-exporter (pg_monitor: statistics views, no table data).
PW=$(openssl rand -hex 24)
kubectl -n village exec postgres-0 -- psql -U village -d aghour_services_production \
  -c "CREATE ROLE metrics LOGIN PASSWORD '$PW'; GRANT pg_monitor TO metrics;"
kubectl -n observability create secret generic postgres-exporter \
  --from-literal=DATA_SOURCE_NAME="postgresql://metrics:$PW@postgres.village.svc:5432/aghour_services_production?sslmode=disable"

kubectl -n observability create secret generic grafana-admin \
  --from-literal=admin-user=admin --from-literal=admin-password="$(openssl rand -base64 18)"

# Telegram: create a bot with @BotFather, send it a message, then read the chat id from
# https://api.telegram.org/bot<TOKEN>/getUpdates. Grafana will not start without this Secret.
kubectl -n observability create secret generic grafana-telegram \
  --from-literal=TELEGRAM_BOT_TOKEN=... --from-literal=TELEGRAM_CHAT_ID=...
```

**2. The stack.** Copy `deploy/observability` to the server, then:

```bash
kubectl apply -k deploy/observability
kubectl -n observability get helmcharts,jobs,pods -w   # helm-install-* jobs, then the pods
```

**3. The app.** Uncomment `OTEL_EXPORTER_OTLP_ENDPOINT` in `deploy/k8s/config.yaml` (it ships off,
so merging this changes nothing until the stack exists). Build the image with
`--build-arg APP_REVISION=$SHA` so traces and metrics carry the commit, then roll out as in
`deploy/k8s/README.md`.

**4. External checks** (they still fire when the node is gone):

- An HTTP monitor on `https://aghour.dorfsys.com/up` (UptimeRobot, Better Stack…).
- A healthchecks.io check with period 1 day and grace 2 hours. Add its ping URL to the app's Secret
  and the reminders CronJob pings it after each successful run:
  `kubectl -n village patch secret village-env -p '{"stringData":{"HEALTHCHECK_URL":"https://hc-ping.com/..."}}'`

## Use

Grafana is not exposed. From your machine:

```bash
ssh -L 3000:127.0.0.1:3000 root@HOST 'kubectl -n observability port-forward svc/grafana 3000:80'
# open http://localhost:3000 — user admin, password:
ssh root@HOST "kubectl -n observability get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d"
```

Dashboards are in the **Aghour** folder:

- **Aghour · API (RED)**: rate, errors and latency by route; 30-day SLOs (99.5% non-5xx, 95% under
  500ms) and the error budget; Traefik vs Rails; requests by app version.
- **Aghour · Business**: the review queue (pending, oldest wait, review time), requests by plan and
  payment method, logins and sign-ups, notifications, the daily reminders job.
- **Aghour · Runtime & Infra**: Puma threads, DB pool, Ruby memory and GC; pods; node; Postgres;
  the collector itself and Prometheus' series count.

Traces: **Explore → Tempo**, or from a Loki log line through its `trace_id`. Logs: **Explore → Loki**,
`{service_name="aghour-api"}`.

To import a dashboard into another Grafana: **Dashboards → New → Import**, upload the JSON from
`dashboards/` and pick a Prometheus datasource in the `datasource` variable.

## Change

- **A dashboard.** Edit the JSON in `dashboards/`, or edit in a scratch Grafana and paste the exported
  JSON over the file, keeping `uid` and the `${datasource}` variable. Then `kubectl apply -k`; Grafana
  picks the file up within a minute. Provisioned dashboards are read-only in the UI on purpose: git is
  the source of truth.
- **An alert.** `grafana-alerting/rules.yaml`, then apply and restart Grafana
  (`kubectl -n observability rollout restart deploy/grafana`).
- **A metric.** Declare it in `Observability::Metrics::DEFINITIONS` (`lib/observability/metrics.rb`)
  with the attribute keys it may carry, and record it with `Observability::Metrics.increment/record`.
  Attribute values must come from a closed set; an undeclared key raises in development and test.
  OTel names map to Prometheus by replacing `.` with `_` and adding the unit and `_total`
  (`aghour.reminders.runs` → `aghour_reminders_runs_total`, `…review.wait` in `s` → `…_seconds`).
- **A chart version.** Bump `spec.version` in the HelmChart and read the chart's changelog first.
  The Grafana-community charts have shipped several majors in weeks.

## Alerts

All Grafana-managed (`grafana-alerting/rules.yaml`), sent to Telegram.

| Alert | Fires when |
|---|---|
| API has no ready pod | `web` has 0 available replicas for 2m |
| API 5xx ratio above 5% | over 10m, with at least 20 requests |
| API p95 latency above 1s | over 15m, with at least 20 requests |
| Threads waiting for a database connection | the pool has waiters for 5m |
| App is not exporting metrics | no app series for 10m (app or collector down) |
| Daily reminders did not run / failed | no successful run in 26h / any failed run |
| Subscription waiting for review over 24h | the oldest pending subscription is older than a day |
| Postgres is down | `pg_up` is 0 or missing for 2m |
| Pod restarting | more than 2 restarts in 30m (`village`, `observability`) |
| Node memory below 10% / disk below 15% | 10m / 30m |

"Daily reminders did not run" needs 26 hours of history: expect it once on the first day.

## Things to know

- **Cardinality.** The app's labels come from closed sets (routes, enums, error codes), with app
  versions trimmed to major.minor. The Infra dashboard shows `prometheus_tsdb_head_series`; the budget
  for this node is about 10k.
- **`max()`, not `sum()`, for business gauges.** Pending subscriptions, current subscriptions and
  visible firms are read from the database by every web pod. With two replicas, `sum()` doubles them.
- **Gauges cost queries.** Each export (30s) runs four `COUNT`s from the web pod, borrowing a pool
  connection for a few milliseconds.
- **Telemetry is off without `OTEL_EXPORTER_OTLP_ENDPOINT`** (development, test, Vercel).
- **Monitoring shares the node.** If the node dies, Grafana dies with it. The uptime probe and
  healthchecks.io are the alerts that still work.
- **Logs start at the end.** A collector restart skips log lines rather than replaying them.
