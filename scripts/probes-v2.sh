#!/usr/bin/env bash
# Limitation probes on kp-eval with the v2 Patterns (patterns-v2/, engine of feat/resolve-probes).
# The evaluated Patterns are installed, the v2 ones replace their namesakes, then:
#   3 scored runs with the truth as the probe oracle (every probe must yield its true verdict),
#   mutation testing with the v2 Patterns, the KubeVela natural state,
# and the original Patterns are restored and scored once more (43/52/10 as predicted).
# The engine must already be installed (scripts/regression.sh <commit> incluster does it).
# Results: measurements/limits/minikube/<commit>/. Run it under systemd-inhibit.
# Usage: probes-v2.sh <commit>
set -uo pipefail
EVAL="$(cd "$(dirname "$0")/.." && pwd)"
S="$EVAL/scripts"
C="${1:?usage: probes-v2.sh <commit>}"
export KP_COMMIT="$C"
source "$EVAL/env/versions.env"
kubectl config use-context "$KP_PROFILE" >/dev/null
OUT="$EVAL/measurements/limits/minikube/$C"; mkdir -p "$OUT"
step() { printf '\n==> [%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
installed="$(kubectl -n "$KP_NAMESPACE" get cronjob "${KP_RELEASE}-cronjob" -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}')"
[[ "$installed" == "$KP_IMAGE" ]] || { echo "installed image is $installed, not $KP_IMAGE" >&2; exit 2; }

install_v2() {
  "$S/apply-patterns.sh" >/dev/null
  find "$EVAL/patterns-v2" -mindepth 2 -maxdepth 2 -name '*.yaml' -print0 | sort -z | xargs -0 -I{} kubectl apply -f {} >/dev/null
  echo "installed: $(kubectl get patterns.kubepattern.dev -o json | jq '[.items[] | select(.metadata.labels["kubepattern.dev/suite"] == "eval-v2")] | length') v2 of $(kubectl get patterns.kubepattern.dev --no-headers | wc -l) Patterns"
}

step "v2 Patterns over the evaluated ones"
install_v2 | tee "$OUT/patterns.txt"

step "RQ2 with the v2 Patterns: 3 runs, probes scored against the truth"
for r in 1 2 3; do
  dir="$("$S/run-once.sh" "probes/v2-$C-r$r" | tail -1)"
  "$S/score.py" "$dir/smells.json" --probe-expect truth --out "$OUT/rq2-v2-r$r" | tail -1
  echo "score exit=${PIPESTATUS[0]} smells=$(jq '.items | length' "$dir/smells.json") $(jq -c '{seconds: ((.completion | fromdate) - (.start | fromdate)), apiRequests}' "$dir/summary.json")"
done | tee "$OUT/rq2-v2.txt"

step "mutation testing with the v2 Patterns"
MUTATION_LABEL="probes/v2-$C-mutation" MUTATION_OUT="$OUT/mutation-v2" "$S/mutate.sh" 2>&1 | grep -E "^mutants|^  (extra|lost)" | tee "$OUT/mutation-v2.txt"
install_v2 >/dev/null  # the revert re-applies the scenarios, not the Patterns; keep the v2 set explicit

step "KubeVela natural state (original catalogue Patterns, new engine)"
"$S/natural-findings.sh" 2>&1 | tail -3 | tee "$OUT/natural.txt"

step "restore the original Patterns"
"$S/apply-patterns.sh" >/dev/null
dir="$("$S/run-once.sh" "probes/v1-$C-restored" | tail -1)"
"$S/score.py" "$dir/smells.json" | tail -1 | tee "$OUT/restored.txt"
echo "score exit=${PIPESTATUS[0]}" | tee -a "$OUT/restored.txt"
step "done"
