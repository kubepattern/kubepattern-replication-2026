#!/usr/bin/env bash
# Krateo limitation probes on kp-krateo with the v2 Patterns (patterns-v2/, engine of feat/resolve-probes).
# The given Patterns are installed, the v2 ones replace their namesakes (and add krateo-restaction-manager-missing,
# the smell only Kyverno could express), then 3 runs are scored against the truth: every G-probe must yield its
# true verdict; scope probes (gaps of the given Patterns) are kept as given. The given Patterns are then restored
# and scored once more (55/0/0/121, 25/25 probes as predicted).
# The engine must already be installed (scripts/regression.sh <commit> does it).
# Results: measurements/limits/minikube/<commit>/krateo/. Usage: probes-v2.sh <commit>
set -uo pipefail
KRATEO="$(cd "$(dirname "$0")/.." && pwd)"
EVAL="$(cd "$KRATEO/.." && pwd)"
C="${1:?usage: probes-v2.sh <commit>}"
source "$KRATEO/env/krateo.env"
export KP_COMMIT="$C"
source "$EVAL/env/versions.env"
kubectl config use-context "$KP_PROFILE" >/dev/null
S="$EVAL/scripts"; OUT="$EVAL/measurements/limits/minikube/$C/krateo"; mkdir -p "$OUT"
TRUTH="$KRATEO/scenario/ground-truth.csv"
step() { printf '\n==> [%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
installed="$(kubectl -n "$KP_NAMESPACE" get cronjob "${KP_RELEASE}-cronjob" -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}')"
[[ "$installed" == "$KP_IMAGE" ]] || { echo "installed image is $installed, not $KP_IMAGE" >&2; exit 2; }

step "v2 Patterns over the given ones"
kubectl apply -f "$KRATEO/patterns/" >/dev/null
kubectl apply -f "$KRATEO/patterns-v2/" >/dev/null
kubectl get patterns.kubepattern.dev --no-headers | wc -l | sed 's/^/installed Patterns: /' | tee "$OUT/patterns.txt"

step "3 runs, G-probes scored against the truth (scope probes as predicted)"
for r in 1 2 3; do
  dir="$("$S/run-once.sh" "krateo/probes-v2-$C-r$r" | tail -1)"
  "$S/score.py" "$dir/smells.json" --truth "$TRUTH" "$KRATEO/scenario/ground-truth-kyverno-only.csv" \
    --probe-expect truth --scope-as-predicted --out "$OUT/v2-r$r" | tail -1
  echo "score exit=${PIPESTATUS[0]} smells=$(jq '.items | length' "$dir/smells.json") $(jq -c '{seconds: ((.completion | fromdate) - (.start | fromdate)), apiRequests}' "$dir/summary.json")"
done | tee "$OUT/v2.txt"

step "restore the given Patterns"
kubectl delete patterns.kubepattern.dev krateo-restaction-manager-missing --ignore-not-found >/dev/null
kubectl apply -f "$KRATEO/patterns/" >/dev/null
dir="$("$S/run-once.sh" "krateo/probes-v1-$C-restored" | tail -1)"
"$S/score.py" "$dir/smells.json" --truth "$TRUTH" | tail -1 | tee "$OUT/restored.txt"
echo "score exit=${PIPESTATUS[0]}" | tee -a "$OUT/restored.txt"
step done
