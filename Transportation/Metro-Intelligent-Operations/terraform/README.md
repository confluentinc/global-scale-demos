# Metro Pipeline — Terraform (Confluent Cloud + Docker, one `apply`)

A single Terraform config that deploys the **entire** metro streaming demo end to end:

1. A Confluent Cloud environment, Basic Kafka cluster, Schema Registry, the raw
   `metro-camera-events` topic, a Flink compute pool, and the Flink SQL
   aggregation job.
2. A Docker image + running container for the data-generator producer
   (`python-producer.py`), wired up with real credentials for the cluster just created.
3. A Docker image + running container for the live map (`live-map/`), published on
   `http://localhost:8765`.

Run `terraform apply` once, open a browser, watch trains move. Run `terraform destroy`
once, everything (cloud resources *and* local containers/images) is gone.

## Architecture

```
                    ┌─────────────────────────────────────────────┐
                    │              Confluent Cloud                 │
 terraform apply →  │  environment → Kafka cluster (Basic)          │
                    │       → topic: metro-camera-events            │
                    │       → Flink compute pool                    │
                    │            → metro_train_departures  (1-min)  │
                    │            → (optional) surge detection +     │
                    │              Bedrock dispatch recommendation  │
                    └───────────────────┬───────────────────────────┘
                                         │ real credentials, injected as
                                         │ container env vars (no manual
                                         │ copy/paste of keys anywhere)
                    ┌────────────────────┴────────────────────┐
                    │              Docker (local)               │
                    │  producer container ──produces──▶ topic   │
                    │  live-map container ──consumes──▶ topic   │
                    │      served on http://localhost:8765       │
                    └─────────────────────────────────────────┘
```

Every Confluent resource's display name is prefixed with `var.project_name`, and both
Docker images/containers are named `${project_name}-producer` / `${project_name}-live-map`,
so multiple people (or multiple deployments by the same person) can coexist in the same
Confluent Cloud org and on the same machine without colliding.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
- [Docker](https://docs.docker.com/get-docker/) (Docker Desktop or a local `dockerd`),
  **running**, before you `terraform apply`
- A Confluent Cloud **Cloud resource management** API key/secret (org- or account-level —
  the kind that can create environments/clusters, *not* a cluster-scoped Kafka key).
  Confluent Cloud Console → your name (top right) → **API Keys** → **+ Add API Key** →
  **My Account** → scope **Cloud resource management**.

## Deploy

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
confluent_cloud_api_key    = "..."
confluent_cloud_api_secret = "..."
project_name               = "metro-demo-yourname"   # must be unique to you
```

Then:

```bash
terraform init
terraform plan     # review what will be created
terraform apply
```

`apply` takes a few minutes — most of the time is Confluent Cloud provisioning the Kafka
cluster and Flink compute pool (both real cloud infrastructure). Docker image builds are
fast (tens of seconds) once those are ready.

When it finishes:

```bash
terraform output live_map_url
```

Open that URL. Give it a minute or two — the producer container needs to emit its first
departures before any trains appear on the map.

## Variables

| Variable | Required | Default | What it controls |
|---|---|---|---|
| `confluent_cloud_api_key` | yes | — | Cloud resource management API key |
| `confluent_cloud_api_secret` | yes | — | Paired secret |
| `project_name` | yes | — | Prefix for every resource/container name; must be unique, lowercase alphanumeric + hyphens, 3-32 chars |
| `cloud` | no | `"AWS"` | Cloud provider for the Kafka cluster + Flink pool |
| `region` | no | `"ap-south-1"` | Region for the Kafka cluster + Flink pool |
| `flink_max_cfu` | no | `10` | Max Confluent Flink Units for the compute pool |
| `run_producer_container` | no | `true` | Set `false` to skip building/running the producer container (e.g. if you'd rather run `python-producer.py` locally for faster iteration) |
| `live_map_port` | no | `8765` | Host port the live map is published on |
| `train_headway_seconds` | no | `600` | Real gap (seconds) between consecutive trains, same line+direction — see the root README for what this actually models |
| `producer_time_scale` | no | `1.0` | Speeds up producer sleeps for testing (e.g. `0.05`). **Leave at `1.0`** for a real deployment |
| `enable_surge_detection` | no | `false` | Deploys the Phase 2 pipeline (see below): `ML_DETECT_ANOMALIES` + an AWS Bedrock model that turns a detected surge into a dispatch recommendation |
| `bedrock_aws_access_key` | if `enable_surge_detection` | `""` | AWS access key with `bedrock:InvokeModel` permission |
| `bedrock_aws_secret_key` | if `enable_surge_detection` | `""` | Paired AWS secret key |
| `bedrock_model_endpoint` | no | Claude Sonnet 4.5 via Bedrock, `us-east-1` | Full Bedrock invoke URL for the text-generation model |

## Outputs

| Output | Notes |
|---|---|
| `live_map_url` | Open this in a browser |
| `environment_id`, `kafka_cluster_id`, `flink_compute_pool_id` | Confluent Cloud resource IDs, useful for `confluent` CLI commands against this deployment |
| `kafka_bootstrap_endpoint`, `kafka_rest_endpoint`, `schema_registry_rest_endpoint` | Connection endpoints |
| `kafka_api_key` / `kafka_api_secret` (sensitive) | Same credentials injected into the containers, if you want to run something else against this cluster |
| `schema_registry_api_key` / `schema_registry_api_secret` (sensitive) | Ditto, for Schema Registry |
| `generated_env_file` | Path to `generated.env` — same credentials in `.env` format, for running `python-producer.py` or `live-map/server.py` locally instead of in Docker |
| `producer_container_name`, `live_map_container_name` | For `docker logs <name>` / `docker restart <name>` |

View any output: `terraform output <name>` (add `-raw` for sensitive/string values without
quotes, e.g. `terraform output -raw kafka_api_secret`).

## What's actually being created

| File | Resources |
|---|---|
| `main.tf` | Environment, Kafka cluster, Schema Registry (data source), Flink region (data source), org (data source) |
| `service-accounts.tf` | One service account (`EnvironmentAdmin`) + Kafka/Schema-Registry/Flink API keys for it |
| `topics.tf` | The raw `metro-camera-events` topic |
| `schema.tf` | Registers `../producer/schemas/metro-camera-events-value.json` (the same schema `producer/python-producer.py` uses) for the topic's value subject, *before* Flink needs it |
| `flink.tf` | The Flink compute pool + the `confluent_flink_statement` job (reusing `../flink-sql/*.sql` directly — no duplicated SQL) |
| `surge-detection.tf` | Optional (gated by `enable_surge_detection`): 4 more `confluent_flink_statement` jobs and a `confluent_flink_connection` to AWS Bedrock — see "Phase 2" below |
| `docker.tf` | `docker_image`/`docker_container` for both the producer and the live map, env vars wired from the Confluent resources above |
| `producer-env.tf` | Writes `generated.env` for anyone who wants to run things outside Docker |

One service account (`EnvironmentAdmin` scope) owns everything — this was confirmed
sufficient to run Flink SQL statements without any additional `FlinkDeveloper`/`Assigner`
role, so the setup stays simple rather than modeling the more elaborate multi-account RBAC
separation Confluent's own examples use for stricter environments.

## Phase 2: station-level surge detection + live-map highlight

Set `enable_surge_detection = true` (plus `bedrock_aws_access_key`/`bedrock_aws_secret_key`)
in `terraform.tfvars` to deploy 5 more Flink SQL statements on top of the base pipeline:

```
metro_train_departures (1-min, per-train totals)
  → metro_station_headcounts          (5-min tumble, per line+direction+station)
  → metro_station_anomaly_scores      (ML_DETECT_ANOMALIES, ARIMA-based, one model
                                        per line+direction+station)
  → metro_station_surge_anomalies     (trailing 1-hour baseline average; keeps only
                                        rows flagged anomalous AND >= 1.5x that
                                        baseline — dips, and mild upticks under 1.5x,
                                        are discarded; JSON output so live-map can
                                        read it without Schema Registry credentials)
  → metro_station_surge_recommendations  (ML_PREDICT against a Bedrock Claude model —
                                        one call per detected surge row, never per
                                        routine window)
```

Detection is pinned to a specific **station**, not just a line — that's what lets
`live-map` draw its highlight circle at an exact point rather than "somewhere on this
line". (`metro_station_anomaly_scores` and `metro_station_surge_anomalies` are two
separate materialized tables, not one statement with two nested `OVER` windows —
Confluent Cloud Flink rejects mixing two different `OVER` window specs in a single
query, confirmed by a real deploy error.)

**Bedrock is deliberately used as little as possible**: `metro_station_surge_anomalies`
already filters down to rows both flagged anomalous by Flink's own ARIMA model *and*
at least 1.5x the recent baseline — `metro_station_surge_recommendations` (and
therefore every Bedrock `ML_PREDICT` call) only ever runs against those already-filtered
rows, not against every 5-minute window. In a quiet network with no surges, Bedrock is
invoked zero times. The prompt also explicitly tells the model not to suggest inserting
a new train within minutes (not operationally realistic) — it asks instead for a short
crowd-alert with one realistic immediate action (extra staff, crowd control, passenger
announcements, prioritizing the next scheduled train).

**Demo aid — synthetic surges**: real ridership noise in this simulator may never
happen to cross the 1.5x-baseline threshold on its own in a short demo session, so
`python-producer.py` runs a background `surge_injector` (gated by the same
`enable_surge_detection` flag, via `ENABLE_SURGE_INJECTION` in `docker.tf`) that, every
5 real minutes (`SURGE_INTERVAL_SECONDS`), picks one random `(line, direction, station)`
and multiplies headcount there by `SURGE_BOOST` (default `3.0x`) for
`SURGE_DURATION_SECONDS` (default `2x` the real train headway, so at least ~2 real
departures from that station are virtually guaranteed to land inside the boosted
window). This is real-wall-clock timed, not `TIME_SCALE`-scaled, since Flink's
5-minute tumbling windows always key off real event time regardless of how fast the
producer is simulating train movement. Set `ENABLE_SURGE_INJECTION=false` on the
producer container to turn this off and rely on organic variance only.

**Live map**: `live-map/server.py` consumes `metro_station_surge_anomalies` directly
(fast — no Bedrock round-trip) and draws a large pulsing red circle at that station for
as long as the surge keeps getting reconfirmed (`SURGE_TTL_SECONDS`, `live-map/server.py`).
This needs no new credentials — that table is deliberately created with
`'value.format' = 'json-registry'` so it decodes the same way the raw camera-events topic
already does. Set `enable_surge_detection = false` and the live-map container's
`ENABLE_SURGE_HIGHLIGHTS` env var follows automatically (`docker.tf`).

Inspect recommendations directly:

```bash
confluent kafka topic consume metro_station_surge_recommendations \
  --cluster $(terraform output -raw kafka_cluster_id) \
  --environment $(terraform output -raw environment_id) -b \
  --value-format json-sr \
  --schema-registry-endpoint $(terraform output -raw schema_registry_rest_endpoint) \
  --schema-registry-api-key $(terraform output -raw schema_registry_api_key) \
  --schema-registry-api-secret $(terraform output -raw schema_registry_api_secret)
```

Each row is `(metro_line, direction, current_station, agg_window_end, total_headcount,
baseline_avg, active_trains, recommendation)` — `recommendation` is Claude's free-text
crowd-alert for that specific detected surge.

To turn this phase off again (e.g. to stop Bedrock billing): set
`enable_surge_detection = false` and `terraform apply` — this tears down exactly the
resources it added (and reconfigures the live-map container to stop looking for surge
events), nothing else.

## Common tasks

**Rebuild after code changes** (e.g. you edited `python-producer.py` or `live-map/`):
```bash
terraform apply
```
Terraform detects the Dockerfile/build-context changed and rebuilds+recreates the
affected container(s) automatically.

**Just restart a container** without touching Terraform state:
```bash
docker restart $(terraform output -raw live_map_container_name)
```

**Tail logs**:
```bash
docker logs -f $(terraform output -raw producer_container_name)
docker logs -f $(terraform output -raw live_map_container_name)
```

**Run the producer locally instead of in Docker** (e.g. for faster edit/test cycles):
```bash
terraform apply -var="run_producer_container=false"
cp generated.env ../.env
cd ../producer && python3 python-producer.py
```

**Point a second live map instance at the same cluster on a different port**:
```bash
terraform apply -var="live_map_port=8766"
```

## Destroy

```bash
terraform destroy
```

Stops and removes both containers and their images, then tears down the Flink
statements, compute pool, topic, API keys, service account, Kafka cluster, and
environment — stopping all associated Confluent Cloud billing. Nothing is left running.

## Troubleshooting

- **`Error: Cannot connect to the Docker daemon`** — start Docker Desktop (or `dockerd`)
  before running `apply`.
- **`Error: ... 401 Unauthorized: invalid API key`** — double-check
  `confluent_cloud_api_key`/`secret` are a **Cloud resource management** key, not a
  cluster-scoped Kafka key (those look similar but are rejected for these API calls).
- **Map loads but no trains appear** — give it a couple of minutes (the producer needs to
  emit its first departures); then check `docker logs $(terraform output -raw
  producer_container_name)` for connection errors.
- **Port already in use** — something else on your machine is using 8765; set
  `-var="live_map_port=<other port>"`.
- **`failed creating table: table already exists`** — destroying a
  `confluent_flink_statement` resource doesn't drop the actual table/topic a `CREATE
  TABLE AS SELECT` created (Terraform only forgets about the *statement*, not the table
  it made). This can leave a stray table behind after a failed-then-fixed apply,
  blocking the retry. Fix: drop it directly, then `terraform apply` again --
  ```bash
  confluent flink statement create drop-stray-table \
    --sql "DROP TABLE IF EXISTS <stray_table_name>;" \
    --compute-pool $(terraform output -raw flink_compute_pool_id) \
    --database $(terraform output -raw kafka_cluster_id) \
    --environment $(terraform output -raw environment_id) \
    --wait
  ```
  `confluent kafka topic list --environment ... --cluster ...` shows you which topics
  actually exist if you're not sure which one is stray.
- **`Table 'metadata' not found` when creating `confluent_flink_statement.train_departure_totals`**
  — fixed as of `schema.tf`; if you still hit this, it means the topic's value schema wasn't
  registered before Flink tried to read it (Flink infers a topic's columns from its Schema
  Registry schema, and doesn't know how to read the JSON's nested `metadata`/`location`/
  `telemetry` objects without it). `terraform apply` again — `schema.tf` should register it
  before the Flink statements run this time.

## Security notes

- Never commit `terraform.tfvars` (it holds real secrets) — already git-ignored, along
  with `*.tfstate`, `.terraform/`, and `generated.env`.
- `terraform.tfstate` contains the plaintext Kafka/Schema-Registry API secrets (Terraform
  has to store resource attributes in state). Treat it like a secrets file: don't commit
  it, and use a remote backend with encryption if you move beyond local, single-person use.
- If you enable Phase 2, `bedrock_aws_access_key`/`bedrock_aws_secret_key` are likewise
  persisted in plaintext in `terraform.tfstate` (Confluent's own connection-resource docs
  call this out too) — the AWS credentials never appear in any Flink SQL statement text,
  but state security matters just as much for them as for the Kafka/Schema-Registry keys
  above.
