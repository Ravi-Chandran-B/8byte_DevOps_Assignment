# Part 3: Monitoring and Logging

## Stack chosen and why
- **Prometheus + Alertmanager + Grafana** via the `kube-prometheus-stack` Helm
  chart — it's the de-facto standard, ships node-exporter and kube-state-metrics
  out of the box, and gets infra + Kubernetes metrics with one install.
- **prometheus-postgres-exporter** as a separate release, because RDS is
  outside the cluster and can't run a sidecar — this exporter runs in-cluster
  and connects out to RDS over the private subnet.
- **Loki + Promtail** (`loki-stack` chart) for logs instead of an EFK stack —
  much lower resource footprint for an assignment-scale cluster, and it plugs
  straight into the same Grafana instance as a datasource, giving metrics and
  logs in one UI ("one pane of glass").

## What gets monitored
| Layer | Metric source | Tool |
|---|---|---|
| Infra (CPU/mem/disk) | node-exporter | kube-prometheus-stack |
| Kubernetes objects (pods, restarts) | kube-state-metrics | kube-prometheus-stack |
| App (request rate, error rate, latency) | app's own `/metrics` endpoint | custom ServiceMonitor |
| Database | postgres_exporter → RDS | prometheus-postgres-exporter |
| App logs | container stdout/stderr | Promtail → Loki |
| System logs | systemd journal | Promtail → Loki |
| Access logs | ALB access logging | ALB → S3 (see note below) |

## Dashboards
Two dashboards are shipped as Grafana-sidecar-loaded ConfigMaps (dashboard-as-code,
so they version with the repo instead of being manually clicked together):
1. **Infrastructure Overview** — node CPU/memory/disk, pod count per namespace, network I/O.
2. **Application & Database Overview** — request rate, error rate, p50/p95/p99 latency,
   Postgres active connections and commit/rollback rate, pod restarts.

## Alerting
`prometheus-rules.yaml` defines a `PrometheusRule` covering:
- High 5xx error rate, high p95 latency (app)
- High node CPU, low disk (infra)
- Postgres down, connection pool near max (db)

Alertmanager routes these to Slack (`slack_configs`); the webhook URL is
injected as a Secret at install time, never committed to the values file.

## Prerequisite: app must expose /metrics
`app-servicemonitor.yaml` assumes `sample-app` (Node/Express, per `app/index.js`)
exposes Prometheus-format metrics at `GET /metrics`. If it doesn't yet, add
`prom-client`:

```bash
cd app && npm install prom-client
```

```js
// index.js — add near the top and before your routes
const client = require('prom-client');
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status'],
  registers: [register],
});
const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status'],
  registers: [register],
});

app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on('finish', () => {
    const labels = { method: req.method, route: req.path, status: res.statusCode };
    httpRequestsTotal.inc(labels);
    end(labels);
  });
  next();
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});
```

Rebuild/push the image and roll the deployment (`kubectl rollout restart
deployment/sample-app -n devops-assignment`) before applying the ServiceMonitor,
otherwise Prometheus will just log scrape failures with no data to show.

## Access-log note
ALB access logs are S3 objects, not container stdout, so they aren't picked
up by Promtail automatically. Enable them via the Terraform `aws_lb` resource
(`access_logs { enabled = true, bucket = ... }` from Part 1) and, if you want
them queryable in Grafana/Loki too, ship them with `promtail`'s S3 target or
a small Lambda that tails new objects into Loki. For this assignment's scope,
raw S3 + lifecycle policy (e.g. 30-day expiry) is sufficient and cheapest.

## Good practices called out
- No secrets (Grafana admin password, RDS DSN, Slack webhook) are hardcoded
  in any values.yaml — all injected via `kubectl create secret` + `existingSecret`
  references, so they never land in git.
- Prometheus TSDB and Grafana are on persistent volumes so a pod restart
  doesn't lose history/dashboards.
- Dashboards and alert rules are defined as code (ConfigMap / CRD) and applied
  via `kubectl apply`, not clicked together in the UI — reproducible and diffable.
- `serviceMonitorSelectorNilUsesHelmValues: false` lets the app team ship its
  own ServiceMonitor in its own namespace without editing the monitoring stack's
  values — decouples app-team and platform-team release cycles.
- Retention (15d metrics, 14d logs) is set explicitly rather than left at
  chart defaults, to bound EBS cost.

## What I'd add with more time
- Grafana behind the Part-1 ALB with OIDC/SSO instead of local admin login.
- A `PrometheusRule` for RDS storage/IOPS approaching provisioned limits
  (needs CloudWatch metrics via `yet-another-cloudwatch-exporter`, since RDS
  doesn't expose disk/IOPS to postgres_exporter directly).
- Long-term metrics storage (Thanos/Mimir) if retention needs to exceed what
  local PVs can hold cost-effectively.

## Challenges & resolutions
- **RDS isn't scrapeable in-cluster by default.** Resolved by running
  `prometheus-postgres-exporter` as its own Deployment with a DSN Secret,
  rather than trying to sidecar it onto the RDS instance (not possible on
  managed RDS).
- **Cross-namespace metric/dashboard discovery.** By default
  `kube-prometheus-stack`'s Prometheus only watches its own namespace for
  ServiceMonitors. Set `serviceMonitorSelectorNilUsesHelmValues: false` (and
  the matching `podMonitorSelectorNilUsesHelmValues`/`ruleSelectorNilUsesHelmValues`)
  so the app's ServiceMonitor and custom PrometheusRule are picked up without
  needing to install the whole stack again in the app's namespace.
- **Secret sprawl vs. Helm values.** Values files are the natural place to put
  config, but several fields (Grafana password, RDS DSN, Slack webhook) are
  secrets. Resolved by pre-creating Kubernetes Secrets and referencing them
  by name (`existingSecret`, `datasourceSecret`) instead of putting values
  directly in the chart's `values.yaml`.