# Keycloak Ops (Kubernetes Manifests + Image)

[![CI](https://github.com/xently/keycloak/actions/workflows/ci-terraform.yml/badge.svg)](https://github.com/xently/keycloak/actions/workflows/ci-terraform.yml)
[![CD](https://github.com/xently/keycloak/actions/workflows/release.yml/badge.svg)](https://github.com/xently/keycloak/actions/workflows/release.yml)

## Introduction

This repository contains:

- A multi-stage [Dockerfile](Dockerfile) to build an optimized Keycloak image with health/metrics enabled and TLS
  materials baked in.
- Kubernetes manifests organized with `kustomize`, including a base and two overlays (**development**, **production**).
- A [Makefile](Makefile) with convenient build and deploy targets.

Audience: Advanced platform/devops engineers working with `kustomize`, `kubectl`, and container build tooling.

## Overview

- Image registry/name: `ghcr.io/xently/keycloak`
- Default Keycloak version TAG (ARG): `26.3.1`
- Health endpoints exposed on management port 9000: `/health/started`, `/health/ready`, `/health/live`
- Base uses a `StatefulSet` for Keycloak and a simple Postgres 17-alpine Deployment for persistence

## Repository Layout

```
.
├── Dockerfile                 # Multi-stage, embeds TLS assets into /opt/keycloak/conf/
├── Makefile                   # build and k8s apply/delete helpers
├── k8s/
│   ├── base/                  # Namespace, StatefulSet (keycloak), Services, and persistence (Postgres + PVC)
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   ├── workloads.yaml     # Keycloak StatefulSet
│   │   ├── services.yaml      # 8080/8443/9000; headless discovery service
│   │   └── persistence/
│   │       ├── workloads.yaml # Postgres StatefulSet (with volumeClaimTemplates)
│   │       └── services.yaml  # Postgres Service
│   └── overlays/
│       ├── development/       # start-dev, relaxed hostname, LB Service, plaintext Secret
│       └── production/        # ExternalSecrets + resource/replica patches
├── server.crt.pem             # Baked into image for dev/test
└── server.key.pem             # Baked into image for dev/test
```

Keep all generic manifests in `k8s/base` and environment-specific changes in `k8s/overlays/<env>`.

## Image Build

The Dockerfile builds an optimized Keycloak image and copies TLS material to `/opt/keycloak/conf/`.

- Build: `make build-images`
- Push: `make build-and-push-images`

If you replace the TLS certs, rebuild the image so that the development overlay picks up the new files.

## Quickstart

1) Build the image (optional if you pull from [GHCR](https://github.com/xently/keycloak/pkgs/container/keycloak)):
    - `make build-images`
    - Optionally push: `make build-and-push-images`

2) Deploy development overlay:
    - `make k8s`
    - Wait for the `keycloak` StatefulSet Pod to become Ready.
    - If your cluster supports `LoadBalancer`, note the external IP of `Service/keycloak-loadbalancer`.

3) Access Keycloak:
    - Dev: https via the LB or via cluster DNS: `https://keycloak.keycloak.svc.cluster.local` (dev overlay config).
    - Admin credentials (dev): see [k8s/overlays/development/secrets.yaml](ops/k8s/overlays/development/secrets.yaml) (
      **_admin_**/**_admin_** by default, not for **production**).

4) Cleanup:
    - `make k8s-delete`

## Common Pitfalls & Troubleshooting

- Namespace is missing: Applying an overlay includes [base/namespace.yaml](ops/k8s/base/namespace.yaml), so the `keycloak`
  namespace will be created automatically.
- Pending PVCs: Ensure a default `StorageClass` exists or set `storageClassName` on PVCs where required.
- External Secrets prerequisites are missing: The production overlay will not reconcile `keycloak-credentials` without
  the External Secrets Operator and a configured `ClusterSecretStore` named `gcp-secret-store`.
- Hostname mismatch: Authentication redirects and issuer URLs will fail if `KC_HOSTNAME` does not reflect the external
  access method. Align Ingress host with `KC_HOSTNAME`.
- Certificates in development: If you change `server.crt.pem`/`server.key.pem`, rebuild the image.
- Database connectivity: Verify `keycloak-database` Service DNS and that credential exists in the `keycloak-credentials`
  Secret.

## Scaling PostgreSQL in Kubernetes

This repo ships a minimal, single-instance PostgreSQL (StatefulSet) suitable for development and simple prod setups.
To "scale" Postgres, consider:

- Vertical scaling (simplest):
    - Increase CPU/memory limits/requests in [k8s/base/persistence/workloads.yaml](ops/k8s/base/persistence/workloads.yaml).
    - Increase PVC size by changing the volumeClaimTemplates storage request. Ensure your StorageClass supports
      expansion.
- High availability / horizontal scaling (recommended for production):
    - Use a PostgreSQL operator/HA distribution to create a primary + replica(s) cluster with automatic failover:
        - Zalando Postgres Operator (Patroni-based): https://github.com/zalando/postgres-operator
        - CrunchyData Postgres Operator: https://access.crunchydata.com/documentation/postgres-operator/
        - Bitnami PostgreSQL HA (Patroni) Helm chart: https://github.com/bitnami/charts/tree/main/bitnami/postgresql-ha
    - These solutions provision a writer Service (primary) and reader Service (replicas). Point Keycloak to the writer
      Service via `KC_DB_URL`.

Important notes:

- Do not scale the current postgres StatefulSet by setting `replicas > 1`: the vanilla `postgres:17-alpine` image does
  not configure replication/failover.
- We added a PodDisruptionBudget and anti-affinity to improve availability and spread scheduling; they are safe with a
  single replica and helpful once you adopt an HA setup.

Example: switching Keycloak to an HA Postgres Service

- After installing an operator/HA chart, set `KC_DB_URL` (in [k8s/base/workloads.yaml](ops/k8s/base/workloads.yaml)) to the
  operator-provided writer Service DNS, e.g.:
    - `jdbc:postgresql://my-postgres-primary.keycloak.svc.cluster.local:5432/authentication`
- Keep `KC_DB_USERNAME`/`KC_DB_PASSWORD` in the `keycloak-credentials` Secret (or ExternalSecret in production).

Rollback path:

- If you need to migrate data from this single-instance DB to an operator-managed cluster, run a `pg_dump`/`pg_restore`
  Job or connect using logical replication, then switch `KC_DB_URL` and roll your Keycloak StatefulSet.

## Style & Conventions

- YAML uses 2-space indentation.
- Group related resources with `---` separators in multi-doc YAML files.
- Keep resource ordering stable to minimize diff noise.

## Useful Commands

- Show make targets: `make help`
- Apply dev overlay: `make k8s`
- Delete dev overlay: `make k8s-delete`
- Apply prod overlay: `make k8s-production`
- Delete prod overlay: `make k8s-production-delete`

## Upgrading Keycloak

- To use a different Keycloak version, build with `--build-arg TAG=<version>` and bump your image tag accordingly, e.g.:
    - `docker build --build-arg TAG=26.3.1 -t ghcr.io/xently/keycloak:26.3.1 .`
    - Update references in manifests or pull the desired tag.

## License

See [LICENSE](LICENSE) for details.