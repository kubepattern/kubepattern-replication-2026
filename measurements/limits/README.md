# Engine update: the DSL limitations G1–G10

The DSL limitation catalogue of the evaluation ([README](../../README.md#limitation-catalogue)) is resolved by new constructs of the Pattern DSL, documented in [`docs/dsl.md`](https://github.com/kubepattern/kubepattern/blob/dev/docs/dsl.md). The work has two stages:

1. **Branch `feat/dsl-limitations`** (cloud session, 2026-10-01, from `dev` @ `a848c98`, whose engine is identical to `50e0222` after the history rewrite): the constructs, the v2 Patterns, and a first validation on an **offline replay** (real API server and CRDs, no controllers), because minikube was not available there. Its results are in the second half of this page.
2. **Branch `feat/resolve-probes`** (2026-10-11/12, from `dev` @ `50e0222`): a review of that engine with fixes and stricter rules, exhaustive tests, and the **validation on minikube** (`kp-eval` and `kp-krateo`) of engine **`aec8df7`**. Its results come first.

## Validation on minikube (engine `aec8df7`)
Scripts: `../../scripts/regression.sh aec8df7` (original Patterns, both parts), `../../scripts/probes-v2.sh aec8df7` (v2 Patterns on kp-eval), `../../krateo/scripts/regression.sh aec8df7` and `../../krateo/scripts/probes-v2.sh aec8df7` (kp-krateo). Outputs: `../regression/aec8df7/` (original Patterns), `minikube/aec8df7/` (v2 Patterns), `snapshot/` (recorded clusters).

**Original Patterns: every result unchanged** (the new engine is a drop-in replacement).

| Check | Reference (`54dc498`) | `aec8df7` |
|---|---|---|
| RQ2, first run + 3 repetitions | 43/52, P = R = 1.00, 10/10 probes as predicted, 0 unlisted | identical (4/4) |
| RQ2b mutation testing | 15/15, reverted == baseline | 15/15, reverted == baseline |
| D8, Job + local run | 46/46 | 46/46 |
| RQ5 CronJob timeline | 9/9 | 9/9 (the laptop suspended between runs 5 and 6; the expectations are per run) |
| Final baseline | 43/52/10 | identical |
| Krateo, 3 in-cluster runs | 55/0/0/121, 25/25 probes | identical |
| Krateo composition lifecycle | 61/51/61, 26/26, reverted == baseline | identical, for KubePattern and Kyverno 1:1 |
| KubeVela natural state | 40/45 unused, 45/45 oracle agreement | identical |

**v2 Patterns: every limitation probe yields its true verdict.**

| Suite | Smells | TP / FP / FN / TN | P / R | Limitation probes | Other |
|---|---|---|---|---|---|
| RQ2, 9 platforms (`../../patterns-v2/` over the originals), 3 runs | 50 | 43 / 0 / 0 / 52 | 1.00 / 1.00 | **10/10 resolved** (G1 3, G3 1, G4 3, G7 1, G8 1, G10 1), 0 unlisted | mutation 15/15, reverted == baseline |
| Krateo, whole ground truth (`../../krateo/patterns-v2/` over the given ones, with the Kyverno-only smell), 3 runs | 79 | 61 / 0 / 0 / 122 | 1.00 / 1.00 | **22/22 G-probes resolved** (G1 5, G2 2, G4 1, G6 11, G7 3); 3 scope probes kept as given; 0 unlisted | equal to the Kyverno best-effort set (79 `fail`, 61/0/0/122) |

- RQ2: 46 + 7 limitation FNs found − 3 limitation FPs gone = 50 Smells.
- Krateo: the 7 rows of `krateo-restaction-manager-missing` (G5, the smell only Kyverno could express) are all correct. On minikube the v2 Patterns also face the **natural** state of the platform (the replay had only the seeded namespaces): of the 11 G6 probes, 9 are natural YamlViewers and RESTActions whose manager is missing, 1 is a seeded YamlViewer and 1 the `portal-composition-page-generic` definition.
- Restoring the original Patterns gives 43/52/10 and 55/0/0/121 again.

**Offline reproduction and ablation** ([`internal/kube/snapshot_test.go`](https://github.com/kubepattern/kubepattern/blob/dev/internal/kube/snapshot_test.go) in the engine repository, which reads a copy of `snapshot/`). The engine's own fetch path recorded both clusters (`snapshot/kp-eval.json.gz`: 228 objects; `snapshot/kp-krateo.json.gz`: 520 objects, Secret data dropped). Served through fake clients, they reproduce every number above in `go test` (`TestSnapshotGroundTruth`: 46/50 Smells on kp-eval, 61/79 on kp-krateo, same scores). `TestSnapshotAblation` replaces one construct at a time with what the original DSL could express; **every one of the 32 resolved probes reverts to its predicted verdict** under the ablation of its own construct:

| Ablation | Probes reverted (RQ2 + Krateo) | Other Smells that change |
|---|---|---|
| `[@]` → `[*]` | 3 + 7 | none |
| a default path read unconditionally, literal defaults dropped | 1 + 0 | 3 negatives become FPs (`ci-new-ca`, `ci-web`, `ss-default-kind`); 7 Krateo RoleBindings become FPs |
| transforms dropped (`apiGroup` criteria dropped) | 3 + 1 | none |
| selector relationships dropped | 1 + 0 | none |
| conditions and criteria on quoted keys dropped | 0 + 3 | 10 positives are lost: the 6 of the Kyverno-only smell, and 4 of `krateo-widget-manager-missing`, whose v2 Pattern quotes a key (`managed-by`) that needs no quotes |
| one concrete kind per target or dependency, no `fromTarget` | 0 + 11 | 23 negatives become FPs: Panels, Pages and Paragraphs reached only through a later kind of a list, and the definitions whose generated kind is no longer read (the original Patterns listed those kinds in separate dependencies instead) |
| owner filter dropped | 1 + 0 | none |
| typed `EQUALS` filters dropped | 1 + 0 | none |

**Cost** (`../regression/aec8df7/whole-cluster.jsonl`, `../regression/aec8df7/scale/`, 54dc498 vs aec8df7, same requests in every cell):

| Measurement | `54dc498` | `aec8df7` |
|---|---|---|
| Whole kp-eval cluster, median of 3 | 0.84 s, 143 requests | 0.84 s, 143 requests |
| S1, 10,000 sources (about 20k objects) | 33.0 s, CPU 39.3 s, 203 MB | **3.3 s, CPU 1.9 s, 155 MB** |
| S1, 5,000 sources | 7.7 s, CPU 8.6 s | 2.8 s, CPU 0.9 s |
| S3, 20 pattern copies | 5.6 s | 2.6 s |
| S2, 800 orphans (805 Smells) | 30.5 s | 30.5 s (bound by the Smell writes at 50 QPS) |
| v2 Patterns, kp-eval / kp-krateo run | – | 4 s and 153–156 requests / 5–6 s and 211–216 requests |

The CPU limit that RQ4 reported at about 20k objects is gone: the dependency side of each relationship is now extracted once per pattern instead of once per target and candidate. The matching is still quadratic in the comparisons, which are now cheap string intersections.

## Review and hardening on `feat/resolve-probes`
| Change | Why |
|---|---|
| The linter rejects `[@]` anchors on independent arrays of one side | their bindings were the cartesian product, empty as soon as one array is: a target was never examined or a dependency never matched |
| The linter rejects a default on a `[*]` path, or a default path with `[*]` | the default applied only when no element had a value: elements without one silently did not count |
| In a Pattern whose target uses `[@]`, every relationship must read the innermost element | a target without the element is not examined, so a relationship on another field was silently never evaluated for it |
| `fromTarget`: the target filters apply; `[@]` reads apiVersion, kind and plural from the same element; `[*]` is rejected | `[*]` kept the first kind only and could pair values of different elements |
| `emptySelector: all \| none` on `selects` / `selectedBy` | an empty selector selects everything in some APIs (PodDisruptionBudget) and nothing in others (Service) |
| The `*Selector` convention follows the parsed field name | `spec['podSelector']` behaved as a label map |
| The dependency side is prepared once per pattern | 1,500 × 1,500 objects: 168 ms → 13 ms; with `[@]` 1,020 ms → 29 ms and 870 MB → 5 MB allocated |
| D2 fixed: a resource type is recorded as fetched only once listed | a type that could not be listed left later patterns with no data |
| D10 found and fixed: the owner walk visits each object once | an ownership cycle made it recurse until the stack overflowed, crashing the run |
| The per-pattern fetch moved to `kube.FetchForPattern` | discovery of kind sets had no test |

**Tests added** to the engine repository (all green with `-race`):
- `internal/analysis/differential_test.go`: 10,000 random cases (objects with nested maps, arrays, scalars and ownership; Patterns with the original constructs only) give exactly the legacy engine's Smells (`legacy_test.go`, the pre-update matching verbatim); 50,000 more random paths for the navigation; the one intended difference (typed `EQUALS`) has its own test.
- Fuzzing: `FuzzParse` (17.6 M executions) and `FuzzValuesMatchesLegacy` (5.5 M) found nothing.
- `internal/linter/repo_patterns_test.go`: all 52 Patterns of the repository lint.
- `internal/kube/fetch_test.go`: kind wildcards, categories, kind lists and `fromTarget` over fake discovery, including 404s, unmapped kinds, forbidden lists and owners.
- `internal/analysis/selectors_test.go`, `internal/cluster/graph_test.go`, the new linter rules in `internal/linter/limits_test.go`.
- `internal/kube/snapshot_test.go`: ground truth and ablation on the recorded clusters (above).

# First validation: offline replay (`feat/dsl-limitations`, 2026-10-01)
Every number in this part was measured on the **offline replay** ([`../../replay/`](../../replay/README.md)): a real `kube-apiserver` v1.34.4 with the pinned CRDs of the nine platforms and no controllers. The replay was checked first against the original results (row "baseline" below). `summary.txt` is the full log of `replay/regression.sh`; per-run scores and rows are in the sub-folders.

## What changed in the engine
| Limitation | Construct | Code |
|---|---|---|
| G1 correlation per element | `[@]` element anchors on the dependency side | `internal/fieldpath`, `resolver.go` |
| G2 "some reference resolves to nothing" | `[@]` on the target side: target filters and relationships share the binding; defective if one element is | `engine.go` (`SelectTargets`) |
| G3 implicit defaults | `targetDefault` / `dependencyDefault` (`{path}` or `{value}`) | `resolver.go` |
| G4 string-encoded references | `targetTransform` / `dependencyTransform`: `apiGroup`, `split`, `regex`, `lowercase` | `linter.ApplyTransform` |
| G5 key escaping | quoted keys `labels['krateo.io/managed-by']` | `internal/fieldpath` |
| G6 kind wildcards, categories | `kind: "*"`, `category`, `kinds`, dependency `fromTarget` | `kube.ExpandRefs`, `kube.FetchForPattern` |
| G7 selectors | `selects` / `selectedBy` with `selectorPath`, optional criteria and `emptySelector` | `resolver.go` (`compileSelectors`) |
| G8 history objects | already expressible with a filter (`metadata.ownerReferences IS_EMPTY`); transients by `spec.for` | – |
| G10 typed filters | `EQUALS` compares booleans and numbers by their string form; `valuesFrom` | `filter.go` |
| (support) | literal criterion sides `targetValue` / `dependencyValue` | `resolver.go` |

G9 (content inside templates and remote references) stays out of scope. The linter validates every new field, the path syntax and the anchor rules. Tests: `internal/fieldpath/fieldpath_test.go`, `internal/analysis/limitations_test.go` (one test per limitation, reproducing its probe), `internal/linter/limits_test.go`; the tests added on `feat/resolve-probes` are listed below.

## Results
**Backward compatibility.** With the original Patterns, the new engine writes exactly the same Smells as the baseline engine, on both suites. Patterns that do not use the new constructs are unaffected.

| Suite (replay) | Engine, Patterns | Smells | TP / FP / FN / TN | P / R | Probes | Mutation |
|---|---|---|---|---|---|---|
| RQ2, 9 platforms | baseline `a848c98`, original | 46 | 43 / 0 / 0 / 52 | 1.00 / 1.00 | 10/10 as predicted (7 FN, 3 FP) | 15/15, reverted = baseline |
| RQ2, 9 platforms | new, original | 46 (identical) | 43 / 0 / 0 / 52 | 1.00 / 1.00 | 10/10 as predicted | 15/15, reverted = baseline |
| RQ2, 9 platforms | new, **v2** (`../../patterns-v2/`) | 50 | 43 / 0 / 0 / 52 | 1.00 / 1.00 | **10/10 resolved** (verdict = truth) | 15/15, reverted = baseline |
| Krateo controlled cases | baseline, given | 39 | 29 / 0 / 0 / 39 | 1.00 / 1.00 | 14/14 as predicted | – |
| Krateo controlled cases | new, given | 39 (identical) | 29 / 0 / 0 / 39 | 1.00 / 1.00 | 14/14 as predicted | – |
| Krateo controlled cases | new, **v2** (`../../krateo/patterns-v2/`) | 45 | 30 / 0 / 0 / 40 | 1.00 / 1.00 | **11/11 limitation probes resolved**; 3 scope probes kept | – |

- The baseline rows equal the minikube results (RQ2: `../effectiveness/`, `../mutation/`; Krateo: `../../krateo/measurements/` restricted to the seeded rows), which validates the replay.
- The 4 extra Smells of RQ2 v2 are the probe balance: the 7 limitation false negatives are now found and the 3 limitation false positives are gone (46 + 7 − 3 = 50).
- Krateo v2 includes `krateo-restaction-manager-missing` (G5), the smell that only Kyverno could express before (`../../krateo/scenario/ground-truth-kyverno-only.csv`, seeded rows: 1 positive, 1 negative).
- The **scope probes** (`page-route`, `panel-kind`, `panel-links`) are gaps of the given Patterns' scope (Routes not considered, Panels matched by name only), not of the engine. They are kept as given, exactly as the Kyverno best-effort set did, so the two remain comparable.

### Probe by probe
| Class | Pattern | Object | Truth | Original Pattern | v2 Pattern |
|---|---|---|---|---|---|
| G1 | `capi-machinetemplate-orphan` | t1 | smell | clean | **smell** |
| G1 | `eso-secretstore-not-used` | ss-g1 | smell | clean | **smell** |
| G1 | `eso-clustersecretstore-not-used` | css-g1b | smell | clean | **smell** |
| G3 | `flux-ocirepository-not-used` | cross-ns | clean | smell | **clean** |
| G4 | `certmanager-clusterissuer-not-used` | ci-foreign-group | smell | clean | **smell** |
| G4 | `crossplane-composition-without-xrd` | app-foreign-group | smell | clean | **smell** |
| G4 | `kubevela-componentdefinition-not-used` | kp-versioned | clean | smell | **clean** |
| G7 | `eso-secretstore-not-used` | ss-selected | clean | smell | **clean** |
| G8 | `certmanager-clusterissuer-not-used` | ci-old-ca | smell | clean | **smell** |
| G10 | `cnpg-cluster-without-scheduledbackup` | db-suspended | smell | clean | **smell** |
| G1 | `page-not-referenced` (Krateo) | page-g1 | smell | clean | **smell** |
| G1 | `paragraph-not-referenced` (Krateo) | para-g1 | smell | clean | **smell** |
| G1 | `krateo-navmenuitem-page-missing` | nav-two | smell | clean | **smell** |
| G1 | `krateo-restaction-endpoint-missing` | ra-ep-g1 | smell | clean | **smell** |
| G2 | `krateo-restaction-endpoint-missing` | ra-ep-mixed | smell | clean | **smell** |
| G1 | `krateo-rolebinding-subject-sa-missing` | rb-sa-g1 | smell | clean | **smell** |
| G2 | `krateo-rolebinding-subject-sa-missing` | rb-sa-mixed | smell | clean | **smell** |
| G4 | `krateo-restaction-not-used` | ra-called | clean | smell | **clean** |
| G6 | `krateo-compositiondefinition-unused` | portal-composition-page-generic | clean | smell | **clean** |
| G6 | `krateo-widget-manager-missing` | yv-managed-missing | smell | clean | **smell** |
| G7 | `panel-not-referenced` (Krateo) | portalcompositionpagegeneric-…-composition-panel | clean | smell | **clean** |

Run-time features exercised on the API server, not only in unit tests: discovery of a category (`fluxcd-appliers` in the Flux v2 Pattern), of a group version (`kind: "*"` over the Krateo widgets in `krateo-restaction-not-used`), and kinds derived from the targets (`fromTarget` in `krateo-compositiondefinition-unused`).

### RQ1 re-classified (analytic)
`expressiveness.csv` re-classifies the 49 relational smells of RQ1 with the new constructs. Four rows are backed by a measurement (replay or unit test), the others are an analytic reading of the semantics, like the original RQ1.

| Verdict | Before | After |
|---|---|---|
| expressible | 27 | 44 |
| partial | 10 | 5 |
| not expressible | 12 | 0 |

The five partial smells: Kratix (the generated request kinds must be named in the Promise status, to verify), Argo Workflows (G8: Workflows are transient, history needed), Tekton (G9: remote resolvers and bundles), Istio (a short host needs a conditional default to become an FQDN), Sealed Secrets (unchanged, not blocked by a catalogued limitation).

## Not re-measured on the replay
At the time, cost and footprint (RQ4 audit, RQ6c), the CronJob timeline (RQ5), RQ8, the Kyverno comparison, the scale sweep and the natural state of the Krateo case study needed minikube; the minikube validation above covers all of them except RQ6 and RQ8, which do not depend on the matching. The replay matching benchmark (`internal/analysis/bench_test.go`, 1,500 × 1,500, 4 CPUs) gave 566 ms for `a848c98` and 189–208 ms for the `feat/dsl-limitations` engine; the prepared dependency side of `feat/resolve-probes` brings it to 13 ms (16 CPUs).
