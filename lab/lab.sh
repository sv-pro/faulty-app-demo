#!/usr/bin/env bash
# Local Kubernetes lab for faulty-app: one healthy service, faults you can switch on.
#
#   lab/lab.sh up               kind cluster + image + healthy base
#   lab/lab.sh list             the fault catalogue
#   lab/lab.sh break <fault>    apply a fault overlay (faults/<fault>)
#   lab/lab.sh heal             apply the healthy base again and wait for it
#   lab/lab.sh check            assert the service is healthy end to end
#   lab/lab.sh status           what you would look at first
#   lab/lab.sh signal <fault>   wait until the fault's symptom is observable
#   lab/lab.sh e2e              every fault: break, observe, heal, check
#   lab/lab.sh down             delete the cluster
#
# Writes only to the kind cluster named $CLUSTER (default faulty-lab) and its
# kubectl context. Never touches another context.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER="${CLUSTER:-faulty-lab}"
CONTEXT="kind-${CLUSTER}"
NS=faulty-lab
IMAGE=faulty-app:dev
REPLICAS=2
WAIT_SECONDS="${WAIT_SECONDS:-150}"

k() { kubectl --context "$CONTEXT" -n "$NS" "$@"; }
say() { printf '\n== %s\n' "$*"; }
die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

faults() { for d in "$ROOT"/faults/*/; do [ -f "$d/fault.yaml" ] && basename "$d"; done; }

field() { # field <fault> <key>: a top-level scalar from fault.yaml
  sed -n "s/^$2: *//p" "$ROOT/faults/$1/fault.yaml" | head -1
}

cmd_up() {
  command -v kind >/dev/null || die "kind is not installed (https://kind.sigs.k8s.io)"
  if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
    say "creating kind cluster $CLUSTER"
    kind create cluster --name "$CLUSTER" --wait 120s
  fi
  say "building $IMAGE"
  docker build -q -t "$IMAGE" "$ROOT/app"
  kind load docker-image "$IMAGE" --name "$CLUSTER"
  cmd_heal
}

cmd_down() { kind delete cluster --name "$CLUSTER"; }

cmd_list() {
  for f in $(faults); do printf '%-18s %s\n' "$f" "$(field "$f" title)"; done
}

cmd_break() {
  local f="${1:?usage: lab.sh break <fault>}"
  [ -f "$ROOT/faults/$f/fault.yaml" ] || die "no such fault: $f (see lab.sh list)"
  say "breaking: $f — $(field "$f" title)"
  kubectl --context "$CONTEXT" apply -k "$ROOT/faults/$f"
}

cmd_heal() {
  say "applying the healthy base"
  kubectl --context "$CONTEXT" apply -k "$ROOT/k8s/base"
  k rollout status deployment/orders --timeout=180s
}

ready_endpoints() {
  k get endpointslices -l kubernetes.io/service-name=orders-api \
    -o jsonpath='{range .items[*]}{range .endpoints[*]}{.conditions.ready}{" "}{end}{end}' \
    | tr ' ' '\n' | grep -c '^true$' || true
}

ready_pod() {
  k get pods -l app=orders \
    -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==true)]}{.metadata.name}{"\n"}{end}' \
    | head -1
}

ready_pods() {
  k get pods -l app=orders \
    -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' \
    | grep -c '^true$' || true
}

# A request to the Service, made from inside a Ready app Pod (no extra image to pull).
request() {
  local pod
  pod="$(ready_pod)"
  [ -n "$pod" ] || return 1
  k exec "$pod" -- python -c \
    "import urllib.request,sys; r=urllib.request.urlopen('http://orders-api/orders', timeout=3); sys.exit(0 if r.status==200 else 1)" \
    >/dev/null 2>&1
}

cmd_check() {
  say "checking the healthy state"
  k rollout status deployment/orders --timeout=180s
  local i
  for i in $(seq 1 30); do
    [ "$(ready_endpoints)" = "$REPLICAS" ] && break
    sleep 2
  done
  [ "$(ready_endpoints)" = "$REPLICAS" ] || die "expected $REPLICAS ready endpoints, got $(ready_endpoints)"
  request || die "request to http://orders-api/orders failed"
  echo "ok: $REPLICAS ready endpoints, http://orders-api/orders answers 200"
}

cmd_status() {
  k get deployment,replicaset,pods -o wide
  k get service,endpointslices
  k get events --sort-by=.lastTimestamp | tail -15
}

# Is the fault's symptom observable right now?
observed() {
  case "$1" in
    endpoints-empty)
      [ "$(ready_endpoints)" = 0 ] && [ "$(ready_pods)" = "$REPLICAS" ] ;;
    image-pull-failed)
      k get pods -l app=orders \
        -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.state.waiting.reason}{" "}{end}{end}' \
        | grep -Eq 'ErrImagePull|ImagePullBackOff' ;;
    readiness-failed)
      k get events --field-selector reason=Unhealthy \
        -o jsonpath='{range .items[*]}{.message}{"\n"}{end}' \
        | grep -q 'Readiness probe failed: HTTP probe failed with statuscode: 404' ;;
    oom-killed)
      k get pods -l app=orders \
        -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.lastState.terminated.reason}{" "}{end}{end}' \
        | grep -q OOMKilled ;;
    *) die "unknown signal: $1" ;;
  esac
}

cmd_signal() {
  local f="${1:?usage: lab.sh signal <fault>}" sig i
  sig="$(field "$f" signal)"
  for i in $(seq 1 $((WAIT_SECONDS / 3))); do
    if observed "$sig"; then echo "observed: $sig"; return 0; fi
    sleep 3
  done
  cmd_status || true
  die "$f: signal $sig not observed within ${WAIT_SECONDS}s"
}

cmd_e2e() {
  cmd_up
  cmd_check
  local f want got results=()
  for f in $(faults); do
    cmd_break "$f"
    cmd_signal "$f"
    want="$(field "$f" service_available)"
    if request; then got=true; else got=false; fi
    [ "$got" = "$want" ] || { cmd_status || true; die "$f: service_available expected $want, got $got"; }
    echo "service_available: $got (expected $want)"
    cmd_heal
    cmd_check
    results+=("$f: broke, observed $(field "$f" signal), service_available=$got, healed")
  done
  say "e2e summary"
  printf '%s\n' "${results[@]}"
}

main() {
  local c="${1:-}"
  shift || true
  case "$c" in
    up|down|list|break|heal|check|status|signal|e2e) "cmd_$c" "$@" ;;
    *) sed -n '2,15p' "$0"; exit 2 ;;
  esac
}

main "$@"
