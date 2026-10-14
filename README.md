# KubePattern replication package (2026)

This repository is the replication package of the evaluation of [KubePattern](https://github.com/kubepattern/kubepattern), a declarative engine that finds relational smells (orphan and unused definitions, dangling references, name clashes) across Kubernetes CRD ecosystems and reports them as `Smell` custom resources. It contains everything needed to rebuild the test environments and re-run every experiment end to end:
- the scripts that build the minikube clusters;
- the evaluated Patterns, the seeded scenarios with their ground truth, and the Kyverno policies of the comparison;
- an offline replay that needs no minikube;
- the measurements behind every reported number.

There are two clusters:
- **`kp-eval`**: nine CRD ecosystems installed side by side (cert-manager, CloudNativePG, External Secrets, Flux, Argo CD, Kargo, Crossplane, KubeVela, Cluster API). It hosts RQ1–RQ6, the engine updates and RQ8.
- **`kp-krateo`**: Krateo PlatformOps 3.0.2 with a blueprint and two compositions. It hosts the Krateo case study, which compares KubePattern and Kyverno on a real platform.

The results, with their discussion, are in [`RESULTS.md`](RESULTS.md) and in the Krateo case study ([`krateo/README.md`](krateo/README.md)).

## Contents
- [Headline results](#headline-results)
- [Repository layout](#repository-layout)
- [Engine under test](#engine-under-test)
- [Requirements](#requirements)
- [Getting the package](#getting-the-package)
- [Environment 1: kp-eval](#environment-1-kp-eval)
- [Environment 2: kp-krateo](#environment-2-kp-krateo)
- [Environment 3: offline replay](#environment-3-offline-replay)
- [Reproducing the experiments](#reproducing-the-experiments)
- [Methodology](#methodology)
- [Measurements](#measurements)
- [Offline tests in the engine repository](#offline-tests-in-the-engine-repository)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Headline results
| Experiment | Result |
|---|---|
| RQ1 Expressiveness | 14 Patterns (26–96 lines of YAML) cover 9 CRD ecosystems with zero engine changes. Of 49 relational smells from the literature, 27 are expressible, 10 partially and 12 not; the blocking limitations form the catalogue G1–G10. After the limitations update: 44 expressible, 5 partial, 0 not. |
| RQ2 Effectiveness | 43 seeded smells and 52 negatives (29 near-misses): precision 1.00, recall 1.00 over 3 runs; 10/10 limitation probes behave as the semantics predict; mutation testing 15/15; natural state 40/45 built-in KubeVela definitions unused, 45/45 agreement with an independent oracle. |
| RQ3 Complementarity | The platforms report 3/50 of these smells, only as transient Warning Events, and 0/50 after the 1 h Event TTL. |
| RQ4 Efficiency | Whole cluster: 23 s, 30 MB, 129 API requests; about 97% of the time is client-side throttling (5 QPS). Memory is linear, matching CPU quadratic. |
| RQ5 CronJob mode | 9 scheduled runs with scripted fixes, injections, a missing CRD, narrowed RBAC and a template rotation: 9/9 snapshots match the prediction. |
| RQ6 Kyverno | A 1:1 Kyverno 1.19 CEL translation reproduces 105/105 verdicts; CEL best-effort policies resolve 10/10 probes; at the same 5-minute period Kyverno keeps 477 MiB always on and uses about 50× the CPU and 23× the API requests. |
| Fix validation | The per-pattern Smell prune keeps 46/46 Smells under overlapping runs (12/46 before), with no regression. |
| Engine update | Client QPS 50/100, a stricter linter and `spec.for`: identical correctness on both clusters, runs about 30× faster (26.2 s → 0.85 s). |
| RQ8 `spec.for` | No transient becomes Active with `for`; every persistent smell is still reported, at a latency cost of `for` rounded up to the next run. |
| Limitations update | New DSL constructs resolve G1–G7 and G10. The original Patterns are unchanged on both clusters; the v2 Patterns resolve 10/10 RQ2 probes and 22/22 Krateo probes; ablating each construct reverts its probes (32/32). |
| Krateo case study | KubePattern and Kyverno agree 1:1 on all 201 ground-truth rows (P = R = 1.00); lifecycle through Krateo 26/26 for both. |

The full tables, per-pattern scores and discussion are in [`RESULTS.md`](RESULTS.md).

## Repository layout
```
kubepattern/    git submodule: the engine source, Helm chart and CRDs (github.com/kubepattern/kubepattern)
env/            versions.env (all pins), minikube-up.sh, audit-policy.yaml, install/NN-*.sh, values/ (RBAC variants)
patterns/       the 14 evaluated Patterns (one folder per platform), kubevela/natural/ (catalogue variant), _robustness/
patterns-v2/    the probed Patterns rewritten with the constructs of the limitations update (same names)
scenarios/      <platform>/{base.yaml, seeds.yaml, [pre|post].sh, ground-truth.csv}, mutations.csv
scripts/        environment, run, scoring, measurement and table scripts (see "Reproducing the experiments")
comparison/     kyverno/: RBAC, GlobalContextEntries and ValidatingPolicies of the RQ6 comparison
                (equivalent/, best-effort/, apicall/, robustness/)
krateo/         the Krateo case study: env/, blueprint/, scenario/, patterns/, patterns-v2/, kyverno/, scripts/,
                measurements/ and its own README
replay/         offline replay: kube-apiserver + etcd + pinned CRDs, controller shim, regression.sh
for/            durations.csv: the spec.for of every evaluated Pattern, with its rationale
measurements/   the CSV, logs and LaTeX tables behind every number (see "Measurements")
RESULTS.md      results of every experiment
```

Every script resolves paths from its own location, so the scripts can be run from anywhere. The examples below assume the repository root as working directory.

## Engine under test
The `kubepattern/` submodule is the only reference to the engine. It is pinned to the release [`v0.1.0`](https://github.com/kubepattern/kubepattern/releases/tag/v0.1.0) (`39fa41b`), the KubePattern release that the paper describes. Its engine and tests are those of `1341079` of the `dev` branch; only the chart version differs. Every script builds and runs that commit: `KP_COMMIT` defaults to the submodule's checked-out commit (short SHA), `scripts/build-image.sh` builds the image `localhost/kubepattern:eval-<KP_COMMIT>` from it with `git archive`, and extracts the binary `bin/kubepattern-<KP_COMMIT>`. `KP_COMMIT=<commit>` selects another commit of the engine repository.

The measurements in `measurements/` were recorded during development with earlier builds of the engine. Their labels appear in folder names, image tags and tables:

| Label | Engine build | Measurements |
|---|---|---|
| `69d4ffd` | as-is engine, evaluated unmodified | RQ1–RQ6, Krateo case study |
| `a814e4a` | per-pattern Smell prune (fixes D8, D9) | fix validation; KubePattern side of RQ6 |
| `wp0` | prune + client QPS 50/100 + linter | QPS validation |
| `54dc498` | engine update: QPS, linter, `spec.for` | engine update regression, RQ8 |
| `aec8df7` | limitations update (G1–G7, G10) | limitations update |

The pinned engine contains all these changes and reproduces the recorded correctness results: the offline tests of the engine repository give 46 / 50 Smells on `kp-eval` and 61 / 79 on `kp-krateo` (original / v2 Patterns) with 32/32 probes reverted by the ablation, and the offline replay gives 43/52/10 with the original Patterns and 10/10 resolved probes with the v2 Patterns. Timing and cost figures belong to the build that recorded them.

## Requirements
**Host.** Linux with KVM, for the minikube `kvm2` driver: the user needs libvirt access (the `libvirt` group or a polkit rule).

| Profile | vCPU | Memory | Disk | Note |
|---|---|---|---|---|
| `kp-eval` | 8 | 16 GiB | 80 GB | about 4 GiB are actually used |
| `kp-krateo` | 12 | 16 GiB | 60 GB | `krateo/env/cluster-up.sh` stops `kp-eval` first |

Run only one profile at a time.

**Tools:**
- `git`, `minikube`, `kubectl`, `helm`, `podman`, `jq`, `openssl`, `curl`;
- `python3` with PyYAML;
- `htpasswd` (httpd-tools), for the Kargo admin hash;
- `systemd-inhibit`, for long runs;
- Go 1.25, only for the offline replay.

**Network.** Outbound HTTPS to the upstream charts, release manifests and container registries of the platforms. The Krateo case study also needs the Krateo marketplace and GitHub releases (`krateoctl`).

**Pinned versions.** All pins are in [`env/versions.env`](env/versions.env); the Krateo pins are in [`krateo/env/krateo.env`](krateo/env/krateo.env).

| Component | Version |
|---|---|
| Kubernetes (minikube, kvm2, docker runtime) | v1.34.4 |
| cert-manager | v1.21.2 |
| CloudNativePG | 1.30.1 |
| External Secrets | chart 2.11.0 |
| Flux | v2.9.5 |
| Argo CD | chart 10.9.2 |
| Kargo | 1.11.4 |
| Crossplane | 2.4.2 (`--enable-operations`) |
| KubeVela | 1.11.0 |
| Cluster API + CAPD | v1.14.2 |
| Kyverno (RQ6 and Krateo only) | v1.19.1 (chart 3.9.1) |
| Krateo PlatformOps | 3.0.2 (`krateoctl` 1.2.1, profile `no-finops`) |
| Krateo blueprints | portal-blueprint-page 1.0.9, portal-composition-page-generic 1.4.3 |
| etcd (offline replay) | v3.6.5 |

## Getting the package
```bash
git clone --recurse-submodules https://github.com/kubepattern/kubepattern-replication-2026.git
cd kubepattern-replication-2026
# if cloned without --recurse-submodules:
git submodule update --init
```
The submodule is a full clone of the engine repository with the pinned commit checked out. To use an existing clone of the engine instead, export `KP_SRC=/path/to/kubepattern` before running any script. The Helm chart and the CRDs are taken from the checked-out tree of `KP_SRC`.

## Environment 1: kp-eval
The cluster hosts the nine platforms. One KubePattern run analyses all of them.

```bash
./env/minikube-up.sh                        # profile kp-eval, Kubernetes v1.34.4, API-server audit log to stdout
./scripts/build-image.sh build              # podman image localhost/kubepattern:eval-<KP_COMMIT> of the submodule's engine
./scripts/build-image.sh extract            # static binary bin/kubepattern-<KP_COMMIT> for out-of-cluster runs
for s in env/install/[0-9]*.sh; do [[ $s == *95-kyverno* ]] || "$s"; done   # KubePattern + 9 platforms (~15 min)
./scripts/apply-scenario.sh                 # base objects and seeded cases of the 9 scenarios
./scripts/apply-patterns.sh                 # the 14 evaluated Patterns
./scripts/verify_fields.py                  # every Pattern path exists in the live CRD schemas
```

What the steps do:
- `minikube-up.sh` copies [`env/audit-policy.yaml`](env/audit-policy.yaml) into `~/.minikube/files/etc/ssl/certs/` and enables the `metrics-server` addon. The audit policy logs only the KubePattern ServiceAccount and the ServiceAccounts of namespace `kyverno`.
- `00-kubepattern.sh` loads the image into the profile and installs the chart from `$KP_SRC/charts/kubepattern`, with the CronJob suspended: every analysis run is triggered explicitly. `KP_SKIP_LOAD=1` skips the image load, for images loaded by hand.
- `60-kargo.sh` writes a random admin password to `env/.kargo-admin` (git-ignored). The evaluation never logs in.

**Baseline check.** Run it before any experiment. It must print `43 52 43 0 0 52 1.00 1.00 10( 10) 0` and exit with status 0: 43 positives and 52 negatives, TP 43, FP 0, FN 0, TN 52, precision and recall 1.00, 10 probes as predicted, 0 unlisted Smells.
```bash
out=$(./scripts/run-once.sh check | tail -1); ./scripts/score.py "$out/smells.json"
```

**Switching engine.** Build the image and the binary of another commit of the engine repository, load the image, and reinstall:
```bash
KP_COMMIT=<commit> ./scripts/build-image.sh all     # build, load into the profile, extract bin/kubepattern-<commit>
KP_COMMIT=<commit> ./env/install/00-kubepattern.sh  # the CronJob stays suspended
```
If `minikube image load` does not land, load a saved tar instead (`podman save -o bin/kubepattern-eval-<commit>.tar localhost/kubepattern:eval-<commit>`, then `minikube -p kp-eval image load <tar>`) and install with `KP_SKIP_LOAD=1`. The images present on the node can be listed with `kubectl get nodes -o json | jq '.items[].status.images[].names[]'`.

**Kyverno (RQ6 only).** Kyverno is installed with `env/install/95-kyverno.sh`, after the rest of the environment; see [RQ6](#reproducing-the-experiments).

**A re-created profile.** `minikube start -p kp-eval` can re-create an empty VM, keeping the profile configuration. [`scripts/rebuild-eval.sh`](scripts/rebuild-eval.sh) rebuilds the whole state in about 13 minutes and checks the baseline. It does not load the KubePattern image: load it first.

**Teardown.** `minikube stop -p kp-eval` keeps the state; `minikube delete -p kp-eval` removes it.

## Environment 2: kp-krateo
The Krateo case study runs on its own profile. The full setup, protocol and results are in [`krateo/README.md`](krateo/README.md).
```bash
cd krateo
./env/cluster-up.sh                 # stops kp-eval and creates kp-krateo (12 vCPU, 16 GiB, Kubernetes v1.34.4)
./env/install/10-krateo.sh          # Krateo 3.0.2 (~10 min)
./env/install/20-chart-repo.sh      # in-cluster Helm repository with the springboot-app blueprint
./env/install/30-blueprint.sh       # PortalBlueprintPage -> CompositionDefinition -> 2 SpringbootApp compositions
./env/install/40-kubepattern.sh     # KubePattern (the submodule's engine), CronJob suspended
./env/install/50-kyverno.sh         # Kyverno 1.19.1, background scan every 5 min, read RBAC
./env/install/60-seeds.sh           # controlled cases and 2 seeded CompositionDefinitions
```
Every Krateo script sources `krateo/env/krateo.env`, so the shared scripts in `scripts/` target `kp-krateo`. When calling shared scripts by hand, run `source krateo/env/krateo.env` from the repository root first.

**Ground-truth check.** Take a snapshot with `krateo/scripts/krateo_oracle.py snapshot <dir>`, then run `krateo/scripts/krateo_oracle.py check <dir>/objects.json`: it must report 201/201 rows consistent with the cluster. The ground truth was generated by the independent oracle `krateo_oracle.py truth` and committed in `krateo/scenario/ground-truth.csv`. Re-creating the compositions renames some generated RoleBindings, so regenerate the ground truth after recreating them.

## Environment 3: offline replay
The replay re-runs the correctness experiments without minikube. It uses a real `kube-apiserver` and `etcd` on localhost, the pinned CRDs of the nine platforms, no controllers, and a controller shim for the objects that controllers would create. It reproduces RQ2 (effectiveness and mutation testing) and the controlled cases of the Krateo case study. It does not reproduce anything that needs running controllers or time (RQ3, RQ4, RQ5, RQ6, RQ8). It needs no container runtime, only Go and outbound HTTPS, and runs in about two minutes. See [`replay/README.md`](replay/README.md).
```bash
cd replay
./up.sh && ./crds.sh && ./scenario.sh && ./krateo.sh
KP_BASE=<commit> ./regression.sh   # a baseline engine vs the engine of KP_SRC -> measurements/limits/
./down.sh --purge
```
Fidelity: on the replay, the engine before the limitations update gives exactly the minikube results (46 Smells, 43/52, 10/10 probes, mutation 15/15).

## Reproducing the experiments
Run long experiments under `systemd-inhibit --what=sleep:idle:handle-lid-switch --mode=block <cmd>`: a host suspend in the middle of a run invalidates it. Keep the KubePattern CronJob suspended, and never overlap two analysis runs (D8).

All commands below run on `kp-eval` from the repository root, unless marked Krateo. Raw per-run archives go to `measurements/raw/` (git-ignored); summaries go to the tracked folders listed below.

### RQ1–RQ5
```bash
# RQ2 effectiveness: 3 repetitions (run 1 exercises the CREATE path, runs 2-3 the UPDATE path)
for i in 1 2 3; do out=$(./scripts/run-once.sh full-$i | tail -1); ./scripts/score.py "$out/smells.json"; done
./scripts/score.py measurements/raw/full-3/*/smells.json --out measurements/effectiveness
./scripts/mutate.sh                                     # RQ2 mutation testing (15 mutants)
./scripts/natural-findings.sh                           # RQ2 natural state (KubeVela catalogue, independent jq oracle)
./scripts/collect_oracles.py                            # RQ3 complementarity (platform conditions and Events)
./scripts/pattern_metrics.py                            # RQ1 Pattern size and primitives
./scripts/cronjob-timeline.sh && ./scripts/timeline_report.py   # RQ5 CronJob timeline (~20 min)
./scripts/scale.py && ./scripts/scale.py cleanup       # RQ4 scale sweeps (~1 h), then restore the evaluation state
./scripts/make_tables.py                                # LaTeX tables in measurements/tables/
```
RQ4 per-run costs come from out-of-cluster runs, `./scripts/perf-local.sh <label>`: wall time, RSS and CPU via `/usr/bin/time -v`, and API requests from the audit log. The RQ1 classification of the 49 smells is analytic: `measurements/expressiveness/expressiveness.csv`, re-classified after the limitations update in `measurements/limits/expressiveness.csv`.

### RQ6: comparison with Kyverno
The audit policy must include the Kyverno ServiceAccounts (it does), and the profile must be restarted after changing it. The recorded KubePattern side used the build `a814e4a`; RQ2 and mutation results are identical with every build.
```bash
KYVERNO_SCAN_INTERVAL=5m ./env/install/95-kyverno.sh
kubectl apply -f comparison/kyverno/rbac.yaml -f comparison/kyverno/globalcontext/
kubectl apply -f comparison/kyverno/equivalent/
for i in 1 2 3; do ./scripts/kyverno-run.sh equivalent-r$i; done   # forced full re-scans, archived
kubectl apply -f comparison/kyverno/best-effort/
for i in 1 2 3; do ./scripts/kyverno-run.sh best-effort-r$i; done
kubectl apply -f comparison/kyverno/equivalent/
./scripts/comparison_effectiveness.py && ./scripts/policy_metrics.py
MUTATION_RUNNER=./scripts/kyverno-run.sh MUTATION_LABEL=kyverno-mutation MUTATION_OUT=measurements/comparison/mutation ./scripts/mutate.sh
# cost: a 1 h idle window, then scripts/cost_report.py <dir> --kp-run <run-once archive> --kp-perf <perf-local line>
./scripts/footprint-sample.sh <dir>/footprint.tsv 3600 10 & ./scripts/audit-harvest.sh <dir>/audit.jsonl 3600 120
# staleness: CronJob */5 unsuspended, then
REPS=5 PERIOD=300 ./scripts/staleness.sh && ./scripts/staleness_report.py <run>
./scripts/kyverno-robustness.sh                         # missing CRD and narrowed RBAC
./scripts/comparison_tables.py                          # measurements/tables/comparison.tex
```
`kyverno-run.sh` restarts the reports controller to force a re-scan, waits until the reports settle, and converts every `fail` result to a smells.json-shaped file with `kyverno_reports_to_smells.py`. Both tools are then scored by the same `score.py`.

### RQ8 and the v2 Patterns
```bash
C=$(git -C kubepattern rev-parse --short=7 HEAD)        # the engine under test
./scripts/regression.sh "$C" incluster                  # RQ2, mutation, D8, RQ5 with the original Patterns -> measurements/regression/$C/
./scripts/probes-v2.sh "$C"                             # v2 Patterns: probes vs truth, mutation, natural state -> measurements/limits/minikube/$C/
KP_BIN=$PWD/bin/kubepattern-$C ./scripts/rq8.sh         # RQ8 on kp-eval (~13 min, uses Kyverno) -> measurements/rq8/
# Krateo: krateo/scripts/regression.sh "$C", krateo/scripts/probes-v2.sh "$C", KP_BIN=$PWD/bin/kubepattern-$C krateo/scripts/rq8-dev-wiring.sh
```
`regression.sh` scales Kyverno's controllers to 0 while it runs and restores them at the end. Expected: the original Patterns give the RQ2 baseline and mutation 15/15; the v2 Patterns resolve 10/10 probes on `kp-eval` and 22/22 on `kp-krateo`.

### Comparisons between development builds
These experiments compared development builds of the engine, named by the labels of [Engine under test](#engine-under-test). Their scripts take the compared builds as binaries `bin/kubepattern-<label>` and images `localhost/kubepattern:eval-<label>`; the recorded results are in the listed folders.

| Comparison | Scripts | Results |
|---|---|---|
| Fix validation: `69d4ffd` vs `a814e4a` | `scripts/gcfix-remeasure.sh`, `scripts/gcfix_compare.py` | `measurements/gcfix/`, `measurements/cronjob-fix/` |
| QPS validation: `a814e4a` vs `wp0` | `scripts/qps-eval.sh`, `krateo/scripts/qps-krateo.sh` | `measurements/qps/` |
| Engine update: `54dc498` vs `a814e4a` | `scripts/regression.sh 54dc498`, `krateo/scripts/regression.sh 54dc498`, `scripts/engine_update_tables.py` | `measurements/regression/54dc498/`, `measurements/cronjob-regr-54dc498/` |
| Limitations update: `aec8df7` vs `54dc498` | `REGR_BASE=54dc498 scripts/regression.sh aec8df7 outcluster`, `scripts/probes-v2.sh aec8df7` | `measurements/regression/aec8df7/`, `measurements/limits/minikube/aec8df7/` |
| Offline replay: the engine before and after the limitations update | `KP_BASE=<commit> replay/regression.sh` | `measurements/limits/` |

### Krateo case study
See [`krateo/README.md`](krateo/README.md), *Protocol*: three KubePattern runs, three Kyverno `equivalent/` and three `best-effort/` runs, the lifecycle through Krateo, and the comparison.
```bash
./krateo/scripts/final-runs.sh                          # every scored run on the same cluster state
./krateo/scripts/lifecycle.sh && ./krateo/scripts/lifecycle_report.py
./krateo/scripts/krateo_compare.py                      # krateo/measurements/*.csv, tables/krateo.tex
```

### Expected results by experiment
| Experiment | Output | Expected |
|---|---|---|
| RQ1 | `measurements/expressiveness/` | 27 / 10 / 12 (as-is); 44 / 5 / 0 after the limitations update |
| RQ2 | `measurements/effectiveness/`, `mutation/`, `natural/` | 43/52, P = R = 1.00, 10/10 probes as predicted, 0 unlisted; mutation 15/15; natural 40/45, agreement 45/45 |
| RQ3 | `measurements/oracles/` | 3/50 reported (transient Events), 0/50 after the Event TTL |
| RQ4 | `measurements/scale/` | whole cluster 23 s, 30 MB, 129 requests; ceiling at about 750 Smells at 5 QPS |
| RQ5 | `measurements/cronjob/` | 9/9 snapshots as predicted |
| Fix validation | `measurements/gcfix/`, `cronjob-fix/` | overlapping runs 46/46 kept (12/46 before); no regression |
| RQ6 | `measurements/comparison/` | 105/105 verdicts equal; best-effort 10/10 probes resolved |
| QPS | `measurements/qps/` | identical results, run time 31.8 s → 1.4 s on Krateo |
| Engine update | `measurements/regression/54dc498/` | unchanged correctness on both clusters; whole cluster 26.2 s → 0.85 s |
| RQ8 | `measurements/rq8/` | 0 transient Active Smells with `for` (2 on kp-eval, 3 on Krateo without it) |
| Limitations update | `measurements/limits/`, `regression/aec8df7/` | originals unchanged; v2 10/10 RQ2 and 22/22 Krateo probes resolved; ablation 32/32 |
| Krateo case study | `krateo/measurements/` | 201/201 rows agree, 55 positives, P = R = 1.00; lifecycle 26/26 |

## Methodology
The evaluation runs KubePattern in CronJob mode. It tests whether KubePattern finds orphan and unused-definition smells across heterogeneous CRD ecosystems, which the platforms themselves do not report, and does so:
- with zero engine changes, through one declarative, target-centric DSL;
- with Patterns and Smells as native custom resources;
- with periodic, self-healing analysis.

The DSL's limits are measured explicitly, as limitation probes.

### Research questions
| RQ | Question | Metrics |
|---|---|---|
| RQ1 Expressiveness | Which relational smells across CRD ecosystems can the DSL express, and at what cost? | verdict (expressible / partial / not) for 49 smells with the blocking limitation; Pattern size and primitives; engine lines changed |
| RQ2 Effectiveness | Does KubePattern find the seeded smells without false alarms? | TP/FP/FN/TN per Pattern; precision and recall on positives and near-misses; limitation probes scored separately; mutation score; agreement with an independent oracle on the natural state |
| RQ3 Complementarity | Do the platforms already report these smells? | fraction of smelly objects with a discriminative unhealthy condition or Warning Event |
| RQ4 Efficiency | How do run time, memory and API load scale? | wall time, peak RSS, API requests by verb and resource, per-phase timing from the audit log; object, Smell and Pattern count sweeps |
| RQ5 CronJob mode | How do Smells behave across consecutive scheduled runs? | Smell lifecycle (create, update in place, GC), convergence after fixes, robustness to a missing CRD and narrowed RBAC, transients during a rotation |
| RQ6 Comparison | How does KubePattern compare with Kyverno on the same smells, cluster and ground truth? | policy vs Pattern size; P/R and probe outcomes of a 1:1 (`equivalent/`) and a `best-effort/` policy set; mutation score; idle footprint, API requests, report writes; detection latency; robustness |
| RQ8 `spec.for` | Does a minimum duration remove snapshot false positives without hiding persistent smells, and at what latency cost? | transient Active and Pending Smells per run; appear and disappear latency; writes per run |

There is no RQ7 in this package.

### Subjects
| Platform | Scenario content |
|---|---|
| cert-manager | 9 ClusterIssuers, Certificates (one rotated), a hand-made CertificateRequest |
| CloudNativePG | 1 live PostgreSQL cluster + 6 object-only Clusters, ScheduledBackups, Poolers |
| External Secrets | fake-provider SecretStores and ClusterSecretStores, ExternalSecrets (top-level and per-entry references), PushSecrets, a ClusterExternalSecret |
| Flux | real OCI sources (podinfo) consumed by suspended HelmReleases and Kustomizations |
| Argo CD | AppProjects, Applications, ApplicationSets (list, cluster and git generators) |
| Kargo | 2 Projects, Warehouses (manual Freight, 24 h discovery), Stages |
| Crossplane | 7 Functions (one Pod each), XRDs of the three scopes, Compositions, Cron/WatchOperations |
| KubeVela | team definitions in namespaces, Applications (custom and built-in types); 45 built-in definitions |
| Cluster API + CAPD | a paused Cluster, KubeadmControlPlane, MachineDeployments, MachineSet, ClusterClass, Docker/Dev machine templates |

Each install script uses only Helm or release manifests (no vendor CLIs).

### Patterns
| Pattern | Relationships | Why it matters |
|---|---|---|
| `crossplane-function-not-used` | 4 × `matchNone` (Composition and Operation/Cron/Watch pipelines, nested `[*]`) | each Function is a running Pod and a supply-chain surface |
| `crossplane-composition-without-xrd` | `matchNone` | the Composition can never be selected |
| `kubevela-{component,trait}definition-not-used` | `matchNone`, nested `[*]`, namespace filter | stale CUE templates in the catalogue |
| `kargo-warehouse-not-requested` | `matchNone` + namespace | the Warehouse keeps polling registries |
| `capi-machinetemplate-orphan` | 5 × `matchNone` over MachineDeployment, MachineSet, KubeadmControlPlane, ClusterClass | leftovers of template rotations |
| `flux-ocirepository-not-used` | 2 × `matchNone`, name + kind + namespace | source-controller pulls artefacts nobody uses |
| `certmanager-clusterissuer-not-used` | 2 × `matchNone`, dependency filters on `issuerRef.kind` | signing material with no consumer |
| `cnpg-cluster-without-scheduledbackup` | `matchNone` + namespace | a database without a backup schedule |
| `cnpg-pooler-name-clashes-with-cluster` | `matchAll` name + namespace | violates the Pooler API contract |
| `argocd-applicationset-generates-nothing` | `owns` + `matchNone` | a zombie generator |
| `argocd-appproject-empty` | `matchNone` + target filter | permissions granted to nobody |
| `eso-secretstore-not-used` | 4 × `matchNone` (top-level, `data[*]`, `dataFrom[*]`, PushSecret) | external credentials with no consumer |
| `eso-clustersecretstore-not-used` | 3 × `matchNone` (ExternalSecret, per entry, ClusterExternalSecret) | cluster-wide credentials with no consumer |

`patterns/kubevela/natural/` holds two catalogue variants for the natural-state experiment; `patterns/_robustness/` holds a Pattern whose target CRD is not installed (RQ5).

### Engine semantics
These semantics were verified in the code of the as-is engine (build `69d4ffd`). The prediction of every probe (`engine_expected`) and the independent Krateo oracle derive from them.

| Aspect | Behaviour |
|---|---|
| Emission | a Smell is written when the relationships evaluate true: all `matchAll`, at least one `matchAny`, no `matchNone` |
| Relationship entry | satisfied if any candidate of `with` satisfies all its criteria; zero candidates means false |
| Multiple dependencies | supported; the same `with` may appear in several entries |
| Custom criteria | only `EQUALS`, as a non-empty intersection of independently extracted value sets: **not correlated per array element** |
| `owns` / `ownedBy` | transitive ownerReference UID walk over the fetched graph |
| Scope | dependencies are cluster-wide; namespace scoping is an explicit criterion |
| Paths | dot-split, `[*]` wildcards (nested supported), no index, no key escaping |
| Filters | `EQUALS` (string values only), `EXISTS`, `IS_EMPTY`, integer comparisons, `ARRAY_SIZE_*` |
| Fetch | lazy: one unpaginated LIST per distinct GVR |
| Missing CRD or RBAC | the Pattern is skipped and logged; the run continues |
| Smell identity | `<pattern>-<targetUID>`, upsert with label `lastScan=<runUUID>` |
| Stale-Smell GC | at the end of the run, every Smell whose `lastScan` differs from the current run is deleted |
| Client | client-go defaults (5 QPS, burst 10), 5-minute timeout |

### Known engine defects
| Id | Defect | Status |
|---|---|---|
| D1 | a missing `config.yaml` falls back to a zero-value configuration | open, not triggered |
| D2 | a GVR is cached before its LIST, so a failed LIST hides data from later Patterns | fixed in `aec8df7` |
| D3 | `suppress` is reset to `false` on every update | fixed in `54dc498` |
| D4 | the linter unit tests lack `plural` | fixed in `54dc498` |
| D5 | `nodeSelector`, `affinity` and `tolerations` break the CronJob template | open, not triggered |
| D6 | Patterns run in Go map order (random) | open; no effect on results, since all GVRs succeed |
| D7 | the same kind read at two apiVersions shares UIDs in the graph | avoided: one apiVersion per kind |
| D8 | two overlapping runs garbage-collect each other's Smells (12/46 survive) | fixed in `a814e4a`; the evaluation never overlaps runs |
| D9 | the global GC is fail-open: Smells of skipped Patterns, or not refreshed before the deadline, are deleted | fixed in `a814e4a` |
| D10 | an ownership cycle makes the owner walk recurse until the stack overflows | fixed in `aec8df7`; not triggered |

### Seeding and ground truth
Every scenario (`scenarios/<platform>/`) has:
- `base.yaml`: the platform in normal use;
- `seeds.yaml`: the seeded cases;
- optional `pre.sh` and `post.sh`: steps that need the controllers, such as a certificate rotation. They are idempotent.

`ground-truth.csv` has the columns `pattern,kind,namespace,name,truth,engine_expected,class,note`. Each object has two labels:
- `truth`: what a correct analysis must report (`smell` or `clean`);
- `engine_expected`: what the verified semantics predict. It differs from `truth` only for probes.

| Class | Meaning | Scoring |
|---|---|---|
| `positive` | a real smell: never used, used only in another namespace, same name but a different kind, reference removed | in scope |
| `negative` | the platform in normal use | in scope |
| `near-miss` | a tricky negative: second array element, second trait of the second component, only an Operation, only a PushSecret, cross-kind same name | in scope |
| `probe-G*` | a case where a documented DSL limitation predicts a FN or FP | separately: prediction accuracy |
| `blocked-upstream` | the misconfiguration cannot be created (admission webhook) | reported only |

Totals: 43 positives, 52 negatives and near-misses, 10 probes, 1 blocked upstream. `score.py` exits non-zero on any in-scope error, failed probe prediction or unlisted Smell. It accepts any smells.json-shaped file, which is how the Kyverno reports are scored.

**Mutation testing** (`scenarios/mutations.csv`, `scripts/mutate.sh`) applies one mutant per Pattern: 14 mutants plus one side effect. The operators are *delete-referrer*, *rename-reference*, *delete-referenced* and *introduce-clash*. The protocol is baseline run → apply all mutants → run → revert → run. A mutant is killed if exactly its target gains a Smell, and restored if the Smell disappears after the revert.

### Oracles
| Evidence | Oracle |
|---|---|
| seeded scenarios | ground truth by construction (`ground-truth.csv`) |
| natural state (KubeVela built-in catalogue) | an independent `jq` computation over the live objects (`scripts/natural-findings.sh`) |
| complementarity (RQ3) | platform status conditions and Warning Events, counted only if discriminative, i.e. absent on clean objects of the same Pattern (`scripts/collect_oracles.py`) |
| field paths | `kubectl explain` on every path used by the Patterns (`scripts/verify_fields.py`, `measurements/field-verification.csv`) |
| Krateo case study | an independent oracle over the live objects (`krateo/scripts/krateo_oracle.py`) |

### Protocols of RQ4 and RQ5
**RQ4.**
- Per-run costs come from out-of-cluster runs of the extracted binary, authenticated as the KubePattern ServiceAccount so that the audit filter applies, plus an audit summary with a phase breakdown.
- Scale sweep (`scale.py`): Flux objects only, all suspended, with the Flux controllers scaled to 0; only the Flux Pattern and its clones are installed.
  - S2, Smells: 1,000 sources and S ∈ {0, 100, 200, 400, 800} orphans, each with a cold (CREATE) and a warm (UPDATE) run, then a stale run (DELETE).
  - S3, Patterns: K ∈ {1, 5, 10, 20} copies of the Pattern.
  - S1, objects: T ∈ {1,000; 2,500; 5,000; 10,000} sources plus T − 100 HelmReleases.
  - Each cell has 5 repetitions.

**RQ5** (`cronjob-timeline.sh`). The CronJob runs at `*/2` for 9 runs, with scripted events between runs:
1. fix 4 smells;
2. inject 3 new ones;
3. add a Pattern whose CRD is missing;
4. narrow RBAC (no `kargo.akuity.io`);
5. restore RBAC;
6. template rotation step 1;
7. template rotation step 2;
8. revert.

After every Job, the Smells (name, UID, creation time) are snapshotted and scored against the expected deltas.

### Limitation catalogue
The probes in the scenarios exercise these limitations of the as-is DSL. The original Patterns keep the predicted verdict. The v2 Patterns (`patterns-v2/`, `krateo/patterns-v2/`) use the constructs of the limitations update, documented in the engine's [DSL reference](https://github.com/kubepattern/kubepattern/blob/dev/docs/dsl.md).

| Id | Limitation | Probes | Predicted | Status after the update | Construct |
|---|---|---|---|---|---|
| G1 | criteria not correlated per array element | CAPI `t1`; ESO `ss-g1`, `css-g1b` | FN | resolved (RQ2 3/3, Krateo 5/5) | `[@]` on the dependency side |
| G2 | no per-element universal quantification | RQ1 only (dangling list references) | not expressible | resolved (Krateo 2/2) | `[@]` on the target side |
| G3 | implicit or overridden namespace/kind defaults | Flux `cross-ns` | FP | resolved (RQ2 1/1) | `targetDefault` / `dependencyDefault` |
| G4 | string-encoded references (group in apiVersion, `name@v1`) | Crossplane `app-foreign-group`; cert-manager `ci-foreign-group`; KubeVela `kp-versioned` | FN, FN, FP | resolved (RQ2 3/3, Krateo 1/1) | transforms `apiGroup`, `split`, `regex`, `lowercase` |
| G5 | no key escaping (labels and annotations with dots) | RQ1 (Strimzi, Dapr) | not expressible | resolved (the Kyverno-only Krateo smell, 7/7 rows) | quoted keys |
| G6 | no kind wildcards or categories | RQ1 (Crossplane MRs, Kratix, Gatekeeper) | not expressible | resolved (Krateo 11/11) | `kind: "*"`, `category`, `kinds`, `fromTarget` |
| G7 | selectors not implemented | ESO `ss-selected` (PushSecret label selector) | FP | resolved (RQ2 1/1, Krateo 3/3) | `selects` / `selectedBy`, `emptySelector` |
| G8 | snapshot hygiene (history objects, transients) | cert-manager `ci-old-ca`; RQ5 rotation | FN; transient | covered (RQ2 1/1) | a dependency filter; `spec.for` (RQ8) |
| G9 | template or remote content | RQ1 (Tekton resolvers, CUE) | out of scope | out of scope | – |
| G10 | filters compare strings only (no booleans) | CNPG `db-suspended` | FN | resolved (RQ2 1/1) | typed `EQUALS`, `valuesFrom` |

Ablating each construct reverts its probes to the predicted verdict (32/32). See [`measurements/limits/README.md`](measurements/limits/README.md).

### Kyverno comparison hypotheses (RQ6)
Kyverno 1.19.1 is used with CEL `ValidatingPolicy` and `GlobalContextEntry`, in Audit mode with background scans. Each hypothesis was measured, not assumed:

| Id | Hypothesis |
|---|---|
| H1 | Kyverno can express the 14 smells through context lookups, but more verbosely (more lines and expressions per smell) |
| H2 | With 1:1-equivalent semantics, Kyverno reaches the same precision and recall on the seeded scenarios |
| H3 | Kyverno's richer expression language overcomes some limitation probes (G1, G3, G4, G10), but not G7 (selectors) or G8 (retained history objects) |
| H4 | Kyverno has a permanent footprint and informer-based reads; KubePattern has zero idle footprint but LISTs everything every run |
| H5 | Neither tool re-evaluates a target when only its dependencies change, so detection latency is bounded by the scan period in both |

The outcome of each hypothesis is in [`RESULTS.md`](RESULTS.md), *RQ6*.

### Threats to validity
- **Construct.**
  - Seeded smells are biased toward detectable forms. Mitigations: near-misses, probes, mutation seeding, and a natural-state experiment with an independent oracle.
  - "Unused" is defined per Pattern; for example, a suspended referrer still counts as a use.
- **Internal.**
  - The known defects D1–D7 are avoided by the scenarios: every CRD exists, and one apiVersion is used per kind.
  - The random Pattern order does not affect results, because all GVRs succeed.
  - The same authors wrote the Patterns, the ground truth and the Kyverno policies. Mitigations: a 1:1 translation and a separately reported best-effort set.
- **External.**
  - The clusters are single-node minikube profiles.
  - Versions are pinned.
  - Objects are realistic but synthetic; the only natural states are the KubeVela catalogue and the Krateo installation.
- **Conclusion.**
  - RQ2 repetitions are deterministic.
  - RQ4 reports medians and IQR over 5 runs per cell.

## Measurements
- `measurements/` holds the summaries behind every number: per-experiment CSV and logs, and `tables/*.tex` (booktabs) generated by `make_tables.py`, `gcfix_compare.py`, `comparison_tables.py`, `engine_update_tables.py` and `krateo_compare.py`.
- Each folder with a protocol of its own has a README: `measurements/limits/`, `qps/`, `rq8/` and `regression/54dc498/`.
- The per-run archives (job, pod log, `smells.json`, audit log) go to `measurements/raw/`. They are git-ignored and not published (about 300 MB); re-running an experiment re-creates them.
- Some CSV, JSON and log files record the paths where they were produced, under `evaluation/` in the engine repository, before this package was split out of it.
- `measurements/limits/snapshot/` holds the recorded state of both clusters, used by the offline tests.

## Offline tests in the engine repository
The engine repository keeps a copy of the evaluated Patterns, the ground truth and the two cluster snapshots in [`internal/kube/testdata/replication/`](https://github.com/kubepattern/kubepattern/tree/dev/internal/kube/testdata/replication). With that copy, `go test ./...` reproduces the ground-truth scores and the ablation without any cluster:
- `TestSnapshotGroundTruth`: 46/50 Smells on `kp-eval`, 61/79 on `kp-krateo`;
- `TestSnapshotAblation`: 32/32 probes reverted;
- `TestRepositoryPatternsLint`: every Pattern lints.

To re-record a snapshot, build the cluster with this package, switch the kubeconfig context to it, and run in the engine repository:
```bash
KP_SNAPSHOT=kp-eval go test -tags snapshot -run TestRecordSnapshot ./internal/kube/
```
Then copy the snapshot to `measurements/limits/snapshot/` here.

## Troubleshooting
- **Overlapping runs.** On the as-is engine, two overlapping analysis runs delete each other's Smells (D8). Keep the CronJob suspended and trigger runs one at a time with `run-once.sh` or `perf-local.sh`.
- **Host suspend.** Run long experiments under `systemd-inhibit --what=sleep:idle:handle-lid-switch --mode=block`. `sleep:idle` alone does not stop a lid-close suspend.
- **The engine binary has no flags.** Running `kubepattern`, even with `--help`, performs a real analysis against the current kubeconfig.
- **Audit log rotation.** The API-server audit log goes to the container's stdout, and the kubelet rotates it. `run-once.sh` and `perf-local.sh` harvest it right after every run. Do the same in custom scripts.
- **Audit policy changes.** Edit `env/audit-policy.yaml`, run `./env/minikube-up.sh` again (or copy the file to `~/.minikube/files/etc/ssl/certs/`), then `minikube stop` and `minikube start` the profile.
- **Image not in the profile.** `minikube image load` can silently fail to land. Check the node's images with `kubectl get nodes -o json | jq '.items[].status.images[].names[]'`, load a saved tar, and install with `KP_SKIP_LOAD=1`.
- **Empty VM after `minikube start`.** If the profile comes back without platforms or scenarios, run `scripts/rebuild-eval.sh`, then the baseline check.
- **libvirt timeout after a reboot.** If `minikube start` fails with a libvirt socket timeout, wait until `virsh -c qemu:///system list` answers, then retry.
- **Ambiguous kinds.** `kubectl wait cluster/...` resolves to the Cluster API `Cluster`. Use fully qualified names such as `clusters.postgresql.cnpg.io/...`.
- **Stopping scripts.** `pkill -f <script-name>` also kills the calling shell, whose command line matches. Stop background jobs by PID.
- **Kyverno by hand on kp-krateo.** Run Helm from the repository root: from `krateo/`, Helm would take the policy folder `./kyverno` as a local chart. `krateo/env/install/50-kyverno.sh` already does this.

## License
Apache License 2.0, see [`LICENSE`](LICENSE). Platform manifests and charts are fetched from their upstream projects under their own licenses.
