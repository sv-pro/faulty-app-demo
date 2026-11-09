# faulty-app-demo

A small service on Kubernetes and a catalogue of faults you can switch on, observe
and heal. Each fault ships with machine-readable ground truth: what was changed,
what an operator sees, and the root cause. That makes it two things at once:

- **a hands-on Kubernetes lab**: break a working deployment the way real releases
  break it, then find the cause with `kubectl` before reading the answer;
- **an eval set for an investigating agent**: an agent with read-only cluster
  access gets the symptoms and must name the root cause; `fault.yaml` is the grader.

Status: lab, not production. Four faults, a local kind cluster, and CI that runs
every fault end to end on a real cluster.

## Quick start

Needs Docker, [kind](https://kind.sigs.k8s.io) and kubectl.

```bash
lab/lab.sh up                    # kind cluster "faulty-lab", image, healthy base
lab/lab.sh check                 # 2 ready endpoints, http://orders-api/orders answers 200
lab/lab.sh list                  # the fault catalogue
lab/lab.sh break readiness-probe # switch a fault on
lab/lab.sh status                # deployments, replicasets, pods, endpoints, events
lab/lab.sh heal                  # back to the healthy base
lab/lab.sh down                  # delete the cluster
```

`lab/lab.sh e2e` runs the whole catalogue: for each fault it breaks the service,
waits until the symptom is observable, checks whether the service still answers,
heals it and checks it again. CI runs exactly this.

The script only talks to the kubectl context `kind-faulty-lab`.

## What runs

```
k8s/base/      Namespace faulty-lab, Deployment orders (2 replicas), Service orders-api
app/           the service: Python standard library only, one file
faults/<id>/   kustomization.yaml (the fault as an overlay on the base) + fault.yaml (ground truth)
lab/lab.sh     up, break, heal, check, status, e2e
tests/         unit tests for the app; a check that every overlay changes exactly what its fault.yaml declares
```

The app serves `/orders`, `/healthz` (liveness) and `/readyz` (readiness, after a
2-second warm-up). The Deployment rolls out with `maxSurge: 1, maxUnavailable: 0`,
so a bad release stalls instead of taking working Pods away. That is why three of
the four faults below leave the service up; seeing that is part of the exercise.

## Fault catalogue

| Fault | What breaks | Service still answers |
|---|---|---|
| [`wrong-selector`](faults/wrong-selector/fault.yaml) | The Service selects no Pods | no |
| [`bad-image-tag`](faults/bad-image-tag/fault.yaml) | A release points at an image tag that does not exist | yes, old Pods |
| [`readiness-probe`](faults/readiness-probe/fault.yaml) | The readiness probe asks for an endpoint the app does not have | yes, old Pods |
| [`oom-kill`](faults/oom-kill/fault.yaml) | A release preloads a cache bigger than its memory limit | yes, old Pods |

To practise, break a fault and diagnose it from the cluster alone. `fault.yaml`
holds the answer, so open it afterwards.

Planned: a Pod that cannot be scheduled (requests above node capacity), a missing
ConfigMap (`CreateContainerConfigError`), a NetworkPolicy that drops traffic, a
liveness probe that restarts a slow but healthy app.

## Ground truth format

```yaml
id: wrong-selector
title: The Service selects no Pods
layer: Service
changes:                      # exactly the paths the overlay changes; tests/test_faults.py enforces it
  - Service/orders-api:spec.selector.app
symptoms: [...]               # what an operator observes
root_cause: ...               # what an investigation should conclude
fix: ...
signal: endpoints-empty       # the machine check lab/lab.sh waits for
service_available: false      # whether http://orders-api still answers during the fault
```

## Tests

```bash
pip install pyyaml
python -m unittest discover -s tests -v   # overlay checks need kubectl, otherwise they are skipped
```
