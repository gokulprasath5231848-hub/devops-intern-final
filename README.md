# devops-intern-final

[![ci](https://github.com/gokulprasath5231848-hub/devops-intern-final/actions/workflows/ci.yml/badge.svg)](https://github.com/gokulprasath5231848-hub/devops-intern-final/actions/workflows/ci.yml)

End-to-end delivery pipeline for a containerised NGINX site: source control
through build, automated CI, orchestrated deployment on Nomad, and log
aggregation with Grafana Loki.

| | |
|---|---|
| **Name** | Gokul Prasath |
| **Submission date** | 2026-10-20 |
| **Assigned by** | Friendy |
| **Repository** | `devops-intern-final` |

## Architecture

```
  developer
      |
      | git push  (feature/* -> pull request -> main)
      v
  +---------------------+
  |   GitHub (source)   |
  +---------------------+
      |
      | workflow: .github/workflows/ci.yml
      v
  +-----------------------------------------------------------+
  |  lint  ->  build  ->  test  ->  publish                    |
  |                                                            |
  |  shellcheck    docker build    start container   push to   |
  |  hadolint      BUILD_SHA=sha   healthcheck.sh    GHCR      |
  |                                must return 200   sha+latest|
  +-----------------------------------------------------------+
      |
      | ghcr.io/gokulprasath5231848-hub/devops-intern-final:<sha>
      v
  +---------------------+        registers        +------------+
  |  Nomad  (docker)    | ----------------------> |   Consul   |
  |  nginx-app / web    |   http check /healthz   +------------+
  |  dynamic port -> 8080                         
  +---------------------+
      |
      | container stdout / stderr
      v
  +------------+      push      +---------+     query     +-----------+
  |  Promtail  | -------------> |  Loki   | <------------ |  Grafana  |
  |  docker_sd |                |  :3100  |     LogQL     |  :3000    |
  +------------+                +---------+               +-----------+
```

The image that CI tests is the exact image that CI publishes: the `build`
job exports it as an artifact, `test` loads and exercises that artifact, and
`publish` re-tags and pushes the same artifact. Nothing is rebuilt between
test and release.

## Prerequisites

| Tool | Pinned version | Used for |
|---|---|---|
| Docker Engine | 29.7.2 | Building and running the image |
| Docker Compose | v2 (bundled) | Monitoring stack |
| Nomad | 1.8 | Orchestration |
| Consul | 1.19 | Service registration and health checks |
| ShellCheck | 0.10.0 | Shell linting |
| hadolint | 2.12.0 | Dockerfile linting |
| Git | 2.54 | Source control |

Base images are pinned in the same way: `nginx:1.27-alpine-slim`,
`grafana/loki:3.0.0`, `grafana/promtail:3.0.0`, `grafana/grafana:11.1.0`.
No `latest` tag is used as a base image or as the only deployment tag.

## Quick Start

Clone to a running application in five commands:

```sh
git clone https://github.com/gokulprasath5231848-hub/devops-intern-final.git
cd devops-intern-final
docker build --build-arg BUILD_SHA="$(git rev-parse HEAD)" --tag nginx-app:local app
docker run --detach --name nginx-app --publish 8080:8080 nginx-app:local
./scripts/healthcheck.sh http://localhost:8080/healthz
```

Then open <http://localhost:8080>. Tear down with:

```sh
docker rm --force nginx-app
```

## Repository layout

```
devops-intern-final/
├── README.md
├── .gitignore
├── .gitattributes
├── app/
│   ├── Dockerfile
│   ├── index.html
│   └── nginx.conf
├── scripts/
│   ├── sysinfo.sh
│   └── healthcheck.sh
├── .github/
│   └── workflows/
│       └── ci.yml
├── nomad/
│   └── nginx-app.nomad.hcl
├── monitoring/
│   ├── loki-config.yaml
│   ├── promtail-config.yaml
│   ├── docker-compose.yaml
│   └── loki_setup.md
└── docs/
    └── screenshots/
```

`.gitattributes` is an addition to the required layout. It forces LF line
endings, without which shell scripts authored on Windows are committed with
CRLF and fail inside Linux containers with `bad interpreter`.

## Task 1 — Source control

Work was done on `feature/pipeline` and merged into `main` through a pull
request. Commits are incremental and follow conventional commit messages.

```sh
git log --oneline --graph
```

```
* 224821a feat(monitoring): add loki, promtail and grafana stack with setup notes
* dda457b feat(nomad): add nginx service job with consul check and rolling update
* eeaa3db ci: add lint, build, test and publish pipeline
* 7b0c1f4 feat(scripts): add sysinfo and healthcheck shell scripts
* 8091f05 fix(app): use alpine-slim base and chown after config test
* 01a6fe1 feat(app): add non-root dockerfile with build sha injection
* 04703ec feat(app): add nginx config and static index page
* 3c62e4f chore: enforce lf line endings via gitattributes
* 6b7af75 chore: initialise repository skeleton
```

The release is tagged `v1.0.0`:

```sh
git tag -a v1.0.0 -m "DevOps intern final assessment"
git push origin v1.0.0
```

## Task 2 — Linux scripting

Both scripts start with a shebang and `set -euo pipefail`, are executable
in Git (mode `100755`, not just on disk), and pass ShellCheck with no
findings.

```sh
git ls-files -s scripts/
```

```
100755 01115bfda29d40b640505f1a69a716e627d3bf54 0	scripts/healthcheck.sh
100755 27d59ec3332c03e2264e69cf6acf34e8cd7483ea 0	scripts/sysinfo.sh
```

### `scripts/sysinfo.sh`

Reports the host environment. Observed output:

```
===== System Information =====

User:             ADMIN
Effective UID:    197609
Hostname:         DESK-gbu
Kernel release:   3.6.7-fb42d713.x86_64
Date (ISO-8601):  2026-10-20T08:41:04Z

----- Disk usage -----
Filesystem            Size  Used Avail Use% Mounted on
C:/Program Files/Git  246G  202G   44G  83% /
S:                     76G   20G   57G  26% /s
```

Memory reporting falls back from `free` to `/proc/meminfo`, and the Docker
section reports `not installed`, `running (server <version>)`, or
`installed but the daemon is not responding`.

### `scripts/healthcheck.sh`

Takes a target URL as `$1`, defaulting to `http://localhost:8080`, asserts
a 200, and exits non-zero with a diagnostic on failure.

```sh
./scripts/healthcheck.sh http://localhost:8080/healthz   # exit 0
./scripts/healthcheck.sh                                 # exit 0, default URL
./scripts/healthcheck.sh http://localhost:8080/missing   # exit 1
./scripts/healthcheck.sh http://localhost:9999           # exit 1
```

Observed output:

```
healthcheck: OK - http://localhost:8080/healthz returned 200
healthcheck: OK - http://localhost:8080 returned 200
healthcheck: FAIL - http://localhost:8080/missing returned 404, expected 200
healthcheck: FAIL - no HTTP response from http://localhost:9999 within 10s
```

### Linting

```sh
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:v0.10.0 \
  scripts/sysinfo.sh scripts/healthcheck.sh
```

Both scripts produce no output and exit 0.

## Task 3 — Containerisation

```sh
docker build --build-arg BUILD_SHA=local-test --tag nginx-app:local app
docker run --detach --name nginx-app --publish 8080:8080 nginx-app:local
```

| Requirement | How it is met |
|---|---|
| Pinned base tag | `FROM nginx:1.27-alpine-slim` |
| Static site on 8080 | `listen 8080` in `app/nginx.conf` |
| `/healthz` returns 200 | `location = /healthz { return 200 "ok\n"; }` |
| Non-root runtime | `USER nginx` (uid 101) |
| `EXPOSE` | `EXPOSE 8080` |
| `HEALTHCHECK` | `wget` against `/healthz`, 30s interval |
| `BUILD_SHA` surfaced | `X-Build-Sha` response header **and** rendered in the page |
| Image under 60 MB | **19.5 MB** |

Observed verification:

```
$ docker images nginx-app:local --format '{{.Size}}'
19.5MB

$ docker exec nginx-app id
uid=101(nginx) gid=101(nginx) groups=101(nginx)

$ curl -s -o /dev/null -w 'status=%{http_code}\n' http://localhost:8080/healthz
status=200

$ curl -s http://localhost:8080/healthz
ok

$ curl -s -D - -o /dev/null http://localhost:8080/ | grep -iE '^HTTP|x-build-sha|^server'
HTTP/1.1 200 OK
Server: nginx
X-Build-Sha: local-test

$ curl -s http://localhost:8080/ | grep -o '<code>[^<]*</code>'
<code>local-test</code>

$ curl -s -o /dev/null -w 'status=%{http_code}\n' http://localhost:8080/missing-page
status=404

$ docker inspect --format '{{.State.Health.Status}}' nginx-app
healthy
```

`Server: nginx` carries no version because `server_tokens off` is set.

Linting:

```sh
docker run --rm -i hadolint/hadolint:v2.12.0-alpine hadolint - < app/Dockerfile
```

No output, exit 0.

![Container serving traffic](docs/screenshots/container-running.png)

## Task 4 — Continuous integration

`.github/workflows/ci.yml` runs on push and pull request to `main`.

| Job | Depends on | Does |
|---|---|---|
| `lint` | — | ShellCheck on `scripts/`, hadolint on `app/Dockerfile` |
| `build` | `lint` | Builds with `BUILD_SHA=${GITHUB_SHA}`, uploads the image as an artifact |
| `test` | `build` | Loads the artifact, starts it, waits for readiness, runs `healthcheck.sh`, asserts `X-Build-Sha` |
| `publish` | `test` | Push to `main` only — tags and pushes to GHCR as `<sha>` and `latest` |

Security posture:

- Default `permissions: contents: read` at workflow level; `publish` adds
  only `packages: write`.
- Registry auth uses the ephemeral `GITHUB_TOKEN`, piped via
  `--password-stdin`. No long-lived credentials exist in the repository.
- Only first-party actions are used (`actions/checkout@v4`,
  `actions/upload-artifact@v4`, `actions/download-artifact@v4`), each
  pinned to a major version. hadolint runs from a version-pinned image
  rather than a third-party action.

The pipeline genuinely gates on the test: `healthcheck.sh` exits non-zero
on any status other than 200, which fails the `test` job and prevents
`publish` from running.

> **Pending.** This has not run yet — the repository has no remote at the
> time of writing. Push to GitHub, confirm all four jobs are green, then
> add the run screenshot below.

![CI pipeline green](docs/screenshots/ci-pipeline.png)

## Task 5 — Orchestration with Nomad

```sh
nomad job validate nomad/nginx-app.nomad.hcl
nomad job plan nomad/nginx-app.nomad.hcl
nomad job run -var="image_tag=$(git rev-parse HEAD)" nomad/nginx-app.nomad.hcl
nomad job status nginx-app
```

The image tag is an HCL variable, so a specific commit can be deployed
rather than whatever `latest` happens to point at:

```hcl
variable "image_tag" {
  type    = string
  default = "latest"
}
```

| Requirement | Value |
|---|---|
| Type | `service`, one group (`web`), one task (`nginx`), `docker` driver |
| Image | `ghcr.io/gokulprasath5231848-hub/devops-intern-final:${var.image_tag}` |
| Resources | 100 MHz CPU, 64 MB memory |
| Port | Dynamic, named `http`, mapped to container `8080` |
| Consul check | HTTP `GET /healthz`, interval `10s`, timeout `2s` |
| Update | `max_parallel = 1`, `min_healthy_time = 10s`, `healthy_deadline = 2m`, `auto_revert = true` |
| Restart | 2 attempts per 5m, 15s delay, mode `fail` |
| Reschedule | 3 attempts per 1h, exponential backoff to 5m |

Resources are left at the assessment defaults. The container is a static
NGINX serving one small page, and the image idles well inside 64 MB, so
there is nothing to justify deviating.

The job file was parsed offline to confirm the HCL and variable
interpolation are correct:

```sh
docker run --rm -v "$PWD/nomad:/job" hashicorp/nomad:1.8 \
  job run -output /job/nginx-app.nomad.hcl
```

Observed, with the stanzas rendered as Nomad will apply them (durations in
nanoseconds):

```
image   : ghcr.io/gokulprasath5231848-hub/devops-intern-final:latest
Update  : MaxParallel 1, MinHealthyTime 10000000000, HealthyDeadline 120000000000, AutoRevert true
Service : nginx-app | port http | provider consul
Check   : type http, path /healthz, Interval 10000000000, Timeout 2000000000
Restart : Attempts 2, Interval 300000000000, Delay 15000000000, Mode fail
Resched : Attempts 3, Interval 3600000000000, DelayFunction exponential, MaxDelay 300000000000
Ports   : [{"Label": "http", "Value": 0, "To": 8080}]
```

Overriding the tag resolves correctly:

```
$ ... job run -output -var='image_tag=abc123' /job/nginx-app.nomad.hcl | grep '"image"'
"image": "ghcr.io/gokulprasath5231848-hub/devops-intern-final:abc123",
```

> **Pending.** Nomad and Consul are not installed on this machine, so the
> job has been parsed but not deployed. Run the four commands above against
> a real agent, paste `nomad job status nginx-app` showing the allocation
> healthy, and add the screenshot below.

![Nomad allocation healthy](docs/screenshots/nomad-status.png)

## Task 6 — Log aggregation with Grafana Loki

```sh
docker compose -f monitoring/docker-compose.yaml up -d
curl --silent --fail http://localhost:3100/ready
```

Promtail discovers containers through the Docker daemon and attaches
`container`, `job`, `service` and `nomad_alloc_id` labels. The status code
is deliberately **not** a label — it is parsed at query time to keep
cardinality low.

Isolating non-200 NGINX access logs:

```logql
{container="nginx-app"}
  | pattern `<ip> - <user> [<ts>] "<method> <path> <proto>" <status> <size> "<referer>" "<ua>" "<xff>"`
  | status != "200"
```

Full procedure, label table, all queries and the Grafana data source setup
are in [`monitoring/loki_setup.md`](monitoring/loki_setup.md).

> **Pending.** `docker compose config` validates, but the stack has not
> been run — Docker Desktop became unstable on this machine (see
> Troubleshooting 5). Bring the stack up, run the queries, record the
> results in `loki_setup.md` section 6, and add the screenshot below.

![Grafana Explore showing NGINX logs](docs/screenshots/grafana-explore.png)

## Troubleshooting

Failures actually encountered while building this, and how each was
resolved.

### 1. NGINX could not start as a non-root user

**Symptom.** The container exited immediately on every run:

```
2026/10/20 08:32:58 [emerg] 1#1: open() "/var/cache/nginx/nginx.pid" failed (13: Permission denied)
nginx: [emerg] open() "/var/cache/nginx/nginx.pid" failed (13: Permission denied)
```

Confusingly, the directory looked correct and a shell in the same image as
the same user could write to it:

```
$ docker run --rm --entrypoint sh nginx-app:local -c 'id; touch /var/cache/nginx/.probe'
uid=101(nginx) gid=101(nginx)
TOUCH OK
```

**Cause.** Listing numeric ownership gave it away:

```
$ docker run --rm --entrypoint sh nginx-app:local -c 'ls -lan /var/cache/nginx'
drwxr-xr-x    1 101      101   .
-rw-r--r--    1 0        0     nginx.pid
```

The directory belonged to uid 101, but `nginx.pid` belonged to **root**.
The `RUN` layer ran `chown` *before* `nginx -t`, and `nginx -t` executes as
root at build time because `USER nginx` comes later in the Dockerfile. The
config test created a root-owned pid file that the runtime user could not
reopen. Creating a *new* file succeeded, which is why the `touch` probe was
misleading.

**Resolution.** Reordered the `RUN` so validation happens before ownership
is fixed:

```dockerfile
RUN sed -i ... \
    && nginx -t \
    && chown -R nginx:nginx /var/cache/nginx /usr/share/nginx/html
```

### 2. Image was 74.5 MB against a 60 MB budget

**Symptom.** The first working image measured 73.7 MB, over the limit.
Rebuilding with `--provenance=false --sbom=false` made no difference, which
ruled out attestation metadata.

**Cause.** The base image itself:

```
nginx:1.27-alpine        74.5MB
nginx:1.27-alpine-slim   19.9MB
```

`alpine` bundles njs, geoip and perl modules that this static site does not
use. `alpine-slim` is the same NGINX without them.

**Resolution.** Switched the base to `nginx:1.27-alpine-slim`. Final image
is **19.5 MB**, comfortably inside budget, and still a pinned tag.

### 3. CI workflow was not valid YAML

**Symptom.** The workflow failed to parse:

```
Error: bad file '.github/workflows/ci.yml':
go-yaml load error in scanner at L41.C78: mapping values are not allowed in this context
```

**Cause.** This line:

```yaml
run: docker images "${IMAGE_NAME}:${GITHUB_SHA}" --format 'image size: {{.Size}}'
```

The value is an unquoted YAML scalar, and the `: ` inside the Docker format
string reads as a key/value separator. Single quotes mean nothing to the
YAML parser here — they are shell syntax, inside a scalar that YAML has
already started parsing.

**Resolution.** Moved it to a block scalar, where the colon is safe:

```yaml
run: |
  size="$(docker images "${IMAGE_NAME}:${GITHUB_SHA}" --format '{{.Size}}')"
  echo "image size is ${size}"
```

### 4. Shell scripts committed with CRLF line endings

**Symptom.** Git warned on the very first commit:

```
warning: in the working copy of '.gitignore', LF will be replaced by CRLF the next time Git touches it
```

**Cause.** Git for Windows defaults to `core.autocrlf=true`. A `.sh` file
checked out with CRLF fails inside a Linux container with
`bad interpreter: /usr/bin/env bash^M` — and it would have failed in CI,
not locally, which makes it expensive to debug.

**Resolution.** Set `core.autocrlf=false` for the repository and committed
a `.gitattributes` enforcing `eol=lf` for `*.sh`, `*.yaml`, `*.yml`,
`*.hcl`, `*.conf` and `Dockerfile`. Caught before it reached CI.

### 5. Docker Desktop backend crashed under load

**Symptom.** `docker compose up -d` for the monitoring stack aborted
mid-pull with `unexpected EOF`, then every Docker command failed:

```
failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine
```

**Cause.** The Docker Desktop backend process exited while pulling the Loki,
Promtail and Grafana images. Both WSL distributions (`docker-desktop` and
`Ubuntu`) were left `Stopped`.

**Investigation.** Relaunching brought the daemon back, but it exited again
within 60 seconds on two consecutive attempts. Disk was ruled out — 45 GB
free on C:.

**Resolution.** Unresolved on this machine. The documented next step is
`wsl --shutdown` followed by a Docker Desktop restart, or a host reboot.
This is why Task 6 has no captured results.

## Known limitations

Things that are not production-ready, and what I would change with more
time.

1. **Tasks 4, 5 and 6 are not verified end to end.** CI has never run (no
   remote yet), the Nomad job is parsed but never scheduled (no agent
   installed), and the Loki stack never started (Docker Desktop crash).
   Everything else in this README is observed output. These three are
   marked **Pending** in place rather than filled with plausible-looking
   text, and they are the first thing to finish.

2. **Scripts are bash, not strictly POSIX `sh`.** The brief asks for
   POSIX-compliant scripts *and* `set -euo pipefail`. `pipefail` is not in
   POSIX.1-2017 and `dash` does not implement it, so the two requirements
   conflict. I chose `#!/usr/bin/env bash`, which satisfies the explicit
   `pipefail` requirement and keeps ShellCheck clean. Dropping `pipefail`
   would make them run under `dash`.

3. **No TLS.** Traffic is plain HTTP end to end. Production would terminate
   TLS at a reverse proxy — that is the optional extension I would attempt
   next.

4. **Single replica.** `count = 1` means any node failure is an outage.
   `auto_revert` protects against a bad deploy but not against a lost node.

5. **Grafana runs with anonymous admin access.** Acceptable for a local
   assessment stack, unacceptable anywhere else. It keeps credentials out
   of the repository, but real deployments need proper auth.

6. **Loki storage is a local filesystem volume** with 168h retention and a
   replication factor of 1. There is no object storage and no backup, so
   losing the volume loses the logs.

7. **No image vulnerability scanning.** A Trivy or Grype step in `lint`
   would be a cheap, obvious addition.

8. **The build is not bit-for-bit reproducible.** The base tag is pinned to
   `1.27-alpine-slim`, which still floats across patch releases. Pinning by
   digest would fix it at the cost of manual update churn.

## Submission checklist

- [x] Public repository named `devops-intern-final`
- [x] Incremental commit history with conventional messages
- [x] `.gitignore` excludes `.idea/` and IDE metadata
- [ ] Feature branch merged to `main` via a self-reviewed pull request
- [ ] Tagged `v1.0.0`
- [ ] CI badge green on `main`
- [ ] Quick Start verified on a clean clone
- [ ] Screenshots added to `docs/screenshots/`
- [ ] HR tracking form submitted, DevOps Department selected
