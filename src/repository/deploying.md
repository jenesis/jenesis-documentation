---
order: 13
title: Running in production
description: Taking Jenesis Repository from a laptop to a team - choosing where the store lives, running several servers, TLS and a reverse proxy, the Helm chart, a template per cloud, signing people in, and backups.
---

The container from [Getting started](/repository/getting-started/) is already the production server - there is
no other build of it. Running it for a team is a matter of four decisions: where the store lives, how many servers
serve it, how it is reached over TLS, and how people sign in.

## Where the store lives

Everything the server holds is in one store, chosen at startup with `JENREG_STORE`:

| `JENREG_STORE` | Store | Required setting |
| --- | --- | --- |
| *(unset)* or `filesystem` | A directory - a Docker volume, a disk, a network share | `JENREG_FILESYSTEM_ROOT` |
| `s3` | AWS S3, or any S3-compatible store such as MinIO or Ceph | `JENREG_S3_BUCKET` |
| `gcs` | Google Cloud Storage | `JENREG_GCS_BUCKET` |
| `azure-blob` | Azure Blob Storage | `JENREG_AZURE_BLOB_CONNECTION_STRING` |

A store that is named but missing a required setting stops the server at startup with a message naming what is
missing - and so does a second store that is fully configured beside the selected one, because a deployment
writing to a store nobody reads is the one mistake that loses data quietly.

**S3.** Credentials come from the usual AWS chain - an instance or task role, a profile, environment variables -
so a server on AWS usually needs none in its configuration:

```bash
JENREG_STORE=s3
JENREG_S3_BUCKET=my-artifacts
JENREG_S3_REGION=eu-central-1                    # us-east-1 by default
JENREG_S3_ENDPOINT=https://minio.internal:9000   # only for an S3-compatible store
```

`JENREG_S3_ACCESS_KEY_ID` and `JENREG_S3_SECRET_ACCESS_KEY` supply keys explicitly, and
`JENREG_S3_SSE_KMS_KEY_ID` encrypts with a KMS key instead of the default server-side encryption.

**Google Cloud Storage** authenticates with Application Default Credentials - Workload Identity on GKE and Cloud
Run - or with a service-account key file named in `JENREG_GCS_CREDENTIALS`.

**Azure Blob** takes the storage account's connection string, and `JENREG_AZURE_BLOB_CONTAINER` names the
container (`jenesis-repository` by default).

Every object store must be reached over `https`, and at startup the server checks that the store honours the
conditional writes it relies on - some S3-compatible services do not, and are refused with the reason.

## Several servers

On an object store the server keeps no state of its own, so any number of them can serve one bucket behind a load
balancer: they coordinate through the store alone, with no lock service and no database. A shared filesystem
works the same way, provided it honours file locks - NFS without its lock daemon does not, and must not be shared.
Background work, such as the scheduled walks, is shared out between the servers rather than repeated by each.

Set `JENREG_CONSISTENCY_ENABLED=true` on every server to have them compare notes: each then records a small
fingerprint of what it has seen, and a server that has fallen behind, runs with different settings, or answers a
path differently from its peers is reported on the **Security posture** page. Give each server a stable name with
`JENREG_CONSISTENCY_NODE_ID` - the host name is used otherwise - so a restarted server is recognised as itself.

## TLS and a reverse proxy

Clients should reach the repository over `https` - some, such as the Go command, refuse to send a credential
otherwise. Put the server behind the load balancer or reverse proxy you already run, terminate TLS there, and tell
the server about it:

```bash
JENREG_PUBLIC_URL=https://repo.example.com         # the address clients use, for the links the server generates
JENREG_TRUSTED_PROXIES=10.0.0.0/8                  # whose X-Forwarded-* headers to believe
```

The console's session cookie is only ever sent over `https`, so the console, too, is used through the proxy.

## Signing people in

Replace the administrator key from Getting started with your identity provider - OpenID Connect, GitHub or LDAP,
as [Access](/repository/access/) describes - and name your administrators:

```bash
JENREG_UI_OIDC_ISSUER_URI=https://login.example.com/realms/main
JENREG_UI_OIDC_CLIENT_ID=jenesis
JENREG_UI_OIDC_CLIENT_SECRET=…
JENREG_UI_ADMINS=oidc/8f3c1a…
```

Then remove `JENREG_UI_ADMIN_KEY` if you set one, set `JENREG_KEY_LOGIN=false` and restart: every person now
signs in as themselves, and every change they make is attributed to them.

## The Helm chart

On Kubernetes, the `jenesis` chart deploys the same image with a service, probes and a volume or an object store.
It is published beside the image, one chart version per release, and each version deploys the image released with
it - so pin the release you want with `--version`:

```bash
helm install jenesis oci://registry-1.docker.io/jenesisbuild/jenesis --version 1.0.0 \
  --set store.backend=s3 --set store.s3.bucket=my-artifacts \
  --set ui.oidc.issuerUri=https://login.example.com/realms/main \
  --set ui.oidc.clientId=jenesis \
  --set secrets.oidcClientSecret=…
```

| Value | Meaning |
| --- | --- |
| `store.backend` | `filesystem` (a 20 GiB volume by default), `s3`, `gcs` or `azure-blob`, with the backend's own values beside it |
| `ui.admins`, `ui.oidc.*`, `ui.github.*` | Sign-in, as above |
| `secrets.*` | Credentials - store keys, client secrets - rendered into a Secret, or `secrets.existingSecret` to use your own |
| `repository.<key>` | Any other setting, as `JENREG_<KEY>` - for example `repository.rate-limit: "1200"` |
| `ingress.*` | An ingress in front of the service |

The server listens on 8080, and the chart points its liveness and readiness probes at `/actuator/health/liveness`
and `/actuator/health/readiness`.

## On a cloud

For a managed container service there is a template per cloud in the repository's
[`deploy/`](https://github.com/jenesis/jenesis-repository/tree/main/deploy) folder. Each one provisions that
cloud's object store, selects it, and runs the published image over it with the store's credential wired in, so a
first deployment is one command:

| Cloud | Template | Runs on | Store |
| --- | --- | --- | --- |
| Google Cloud | [`deploy/gcp`](https://github.com/jenesis/jenesis-repository/tree/main/deploy/gcp) (Terraform) | Cloud Run | `gcs`, as the service's own account |
| AWS | [`deploy/aws`](https://github.com/jenesis/jenesis-repository/tree/main/deploy/aws) (CloudFormation) | ECS Fargate behind a load balancer | `s3`, as the task role |
| Azure | [`deploy/azure`](https://github.com/jenesis/jenesis-repository/tree/main/deploy/azure) (Bicep) | Container Apps | `azure-blob` |
| Scaleway | [`deploy/scaleway`](https://github.com/jenesis/jenesis-repository/tree/main/deploy/scaleway) (Terraform) | Serverless Containers | `s3`, as an IAM application's key |

```bash
cd deploy/gcp
terraform init
terraform apply -var project_id=my-project -var bucket_name=my-artifacts \
  -var 'secrets={JENREG_BOOTSTRAP_KEY="jenk_…", JENREG_UI_ADMIN_KEY="…"}'
```

Every template takes the image as a parameter that defaults to `latest`; pin a release for a deployment that should
not move on its own. Because authentication is on, each takes the two starter credentials as secrets - the API's
bootstrap key and the console's starter key - and any other setting as an environment variable by its `JENREG_*`
name. The Google Cloud, Azure and Scaleway services start private, reachable only through the cloud's own access
control, until a parameter publishes them; the AWS load balancer is public from the start and answers on plain
HTTP until you give it a certificate. The folder's README says what every template takes.

## Backups

The store is the only state, so a backup is a copy of it: the volume or directory, or the bucket, with the
snapshot or replication tooling you already use. A copy restores to any backend - copy the objects with their
names unchanged, point `JENREG_STORE` at the new place, and start the server. **Settings → Settings** also exports
the runtime settings alone, as one file, which is worth keeping beside a large configuration change.

<div class="warning">
  On a bucket with versioning or soft delete, space the collector frees stays billed until the bucket's own
  lifecycle rule expires the old versions - the collector removes the current version and leaves the bucket's
  safety net alone. <a href="/repository/cost/">What it costs to run</a> covers what to check on each provider.
</div>
