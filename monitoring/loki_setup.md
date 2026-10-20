# Loki Setup Notes

Log aggregation for the `nginx-app` deployment: Promtail scrapes container
logs from the Docker daemon, ships them to Loki, and Grafana queries them
with LogQL.

## 1. Starting the stack

From the repository root:

```sh
docker compose -f monitoring/docker-compose.yaml up -d
```

Wait for Loki to report ready (the compose healthcheck polls the same endpoint):

```sh
curl --silent --fail http://localhost:3100/ready
```

Services and ports:

| Service  | Image                  | Port  | Purpose                          |
|----------|------------------------|-------|----------------------------------|
| loki     | `grafana/loki:3.0.0`     | 3100  | Log store and query API          |
| promtail | `grafana/promtail:3.0.0` | 9080  | Scrapes Docker logs, pushes them |
| grafana  | `grafana/grafana:11.1.0` | 3000  | Explore UI                       |

Grafana runs with anonymous admin access so no credentials are stored in
the repository.

## 2. Connecting Grafana to Loki

Grafana does not ship a provisioned datasource here, because the assessment
fixes the contents of `monitoring/`. Add it once by hand:

1. Open <http://localhost:3000>.
2. **Connections -> Data sources -> Add new data source -> Loki**.
3. Set the URL to `http://loki:3100` (the compose service name, not
   `localhost` — Grafana resolves it on the `observability` network).
4. **Save & test**, which should report that the data source is working.

## 3. Label set

Labels come from `monitoring/promtail-config.yaml`. Promtail discovers
containers through `docker_sd_configs` and relabels Docker metadata:

| Label            | Source                                            | Example       |
|------------------|---------------------------------------------------|---------------|
| `container`      | `__meta_docker_container_name`, leading `/` stripped | `nginx-app`   |
| `job`            | Nomad job name label, falling back to `docker`    | `nginx-app`   |
| `service`        | Nomad task name label                             | `nginx`       |
| `nomad_alloc_id` | Nomad allocation id label                         | `a1b2c3d4...` |

Nomad's Docker driver stamps `com.hashicorp.nomad.*` labels onto every
container it starts, which is where `job`, `service` and `nomad_alloc_id`
come from. Containers started outside Nomad (the monitoring stack itself,
or a plain `docker run` of the image) have no such labels, so the final
relabel rule defaults `job` to `docker` and keeps those streams queryable.

Labels are deliberately low-cardinality. The request path and status code
are **not** labels — they are parsed at query time, which is why the
queries below use a `logfmt`/pattern stage rather than a label selector.

## 4. LogQL queries

### 4.1 All logs from the application

```logql
{container="nginx-app"}
```

### 4.2 Only NGINX access logs, isolating non-200 responses

The access log uses the standard combined format, so the status code is
extracted with a `pattern` stage and then filtered:

```logql
{container="nginx-app"}
  | pattern `<ip> - <user> [<ts>] "<method> <path> <proto>" <status> <size> "<referer>" "<ua>" "<xff>"`
  | status != "200"
```

### 4.3 Rate of non-200 responses over five minutes

```logql
sum by (status) (
  rate(
    {container="nginx-app"}
      | pattern `<ip> - <user> [<ts>] "<method> <path> <proto>" <status> <size> "<referer>" "<ua>" "<xff>"`
      | status != "200" [5m]
  )
)
```

### 4.4 Generating a deliberate failure to prove ingestion

With the application running, request a path that does not exist:

```sh
curl --silent --output /dev/null http://localhost:8080/this-path-does-not-exist
```

Query 4.2 should then return that single 404 line.

## 5. Verifying ingestion from the command line

Useful when Grafana is not open — these hit Loki's HTTP API directly:

```sh
curl --silent "http://localhost:3100/loki/api/v1/labels"

curl --silent "http://localhost:3100/loki/api/v1/label/container/values"

curl --silent --get "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={container="nginx-app"}' \
  --data-urlencode 'limit=20'
```

## 6. Results

> **Not yet captured.** The stack configuration is committed and
> `docker compose config` validates, but the live run has not been
> completed on this machine — see section 8. Run the commands in
> sections 1, 4 and 5, paste the real output here, and save the Grafana
> Explore screenshot to `docs/screenshots/grafana-explore.png`.

## 7. Configuration rationale

These are the non-obvious choices in the committed config, and why they are
the way they are. Be ready to explain each one in review.

### 7.1 The Docker socket is mounted into Promtail

`docker_sd_configs` discovers targets by talking to the Docker daemon, so
Promtail needs `/var/run/docker.sock`. It is mounted **read-only** — that is
sufficient for discovery and log streaming, and avoids handing Promtail
write access to the daemon.

### 7.2 Grafana points at `http://loki:3100`, not `localhost`

Inside the Grafana container `localhost` is Grafana itself. The published
port 3100 is only reachable that way from the host. Both containers sit on
the `observability` network, so Docker's embedded DNS resolves the compose
service name `loki`.

### 7.3 Schema is TSDB `v13`, not `boltdb-shipper` `v11`

Loki 3.x expects the TSDB store with schema `v13`. Most examples still
online use `boltdb-shipper` with `v11`, which no longer loads. Enabling
retention also requires `compactor.delete_request_store`, hence the
explicit `filesystem` value.

### 7.4 Status code is parsed at query time, not stored as a label

High-cardinality labels are the standard way to make Loki slow and
expensive. `status` and `path` would add one stream per distinct value, so
they stay in the log line and are extracted with a `pattern` stage when
queried.

## 8. Problems hit and how they were resolved

### 8.1 Docker Desktop stopped responding while pulling the stack

**Symptom.** `docker compose up -d` aborted mid-pull with `unexpected EOF`,
then every subsequent Docker command failed with
`failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine`.

**Cause.** The Docker Desktop backend exited during the large image pulls.
The WSL distributions `docker-desktop` and `Ubuntu` were both left in the
`Stopped` state and the daemon did not recover on its own.

**Investigation.** Relaunching Docker Desktop brought the daemon back, but
it exited again within 60 seconds, twice. Disk was ruled out as the cause
(45 GB free on C:).

**Resolution.** Still open on this machine. Next step is `wsl --shutdown`
followed by a Docker Desktop restart, or a host reboot, then re-run
section 1.

> Sections 6 and 8 are incomplete until the stack has actually been run.
> Once it is up, record any further failures here with the same
> symptom / cause / resolution structure.

## 9. Tearing the stack down

```sh
docker compose -f monitoring/docker-compose.yaml down

docker compose -f monitoring/docker-compose.yaml down --volumes
```

The second form also drops the `loki-data` volume and every ingested log.
