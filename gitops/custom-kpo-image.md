# Custom KPO Controller Image Runbook

This runbook describes how to use a custom-built Karpenter Provider OCI (KPO) controller image with this repo instead of the published chart default.

## Why This Is Needed

This repo currently deploys the published KPO Helm chart from:

- `https://oracle.github.io/karpenter-provider-oci/charts`

and the chart uses its default controller image unless you override it in:

- `gitops/c/kpo/values.yaml`

That means changes in your local KPO source tree are not used by the cluster until you build and push a controller image and point the chart at it.

## Recommended Registry

Recommended target:

- a private OCIR repository in the same tenancy and region as the OKE cluster

Recommended image naming shape:

- `<region-key>.ocir.io/<tenancy-namespace>/kpo/karpenter-provider-oci:<tag>`

Example:

- `iad.ocir.io/mytenancyns/kpo/karpenter-provider-oci:ubuntu-custom-bootstrap-20260818`

Why OCIR is the best default here:

- closest fit for OCI/OKE
- customer-controlled
- stable for Argo/Helm deployments
- avoids depending on a personal local registry

If you use a private registry, the KPO deployment must be able to pull from it. For private OCIR, that usually means adding a Docker registry secret in the `karpenter` namespace and referencing it via Helm `imagePullSecrets`.

## Source Repo

Build from:

- `/home/bd/ora/oracle/karpenter-provider-oci`

The chart consumer repo is:

- `/home/bd/gh/private-oke-karpenter`

## End-to-End Steps

### 1. Choose the image tag

Use a unique immutable tag. Do not reuse `latest`.

Recommended pattern:

- feature name + date
- git commit SHA if available

Examples:

- `ubuntu-custom-bootstrap-20260818`
- `ubuntu-custom-bootstrap-<git-sha>`

### 2. Log in to OCIR

Get the tenancy namespace:

```bash
oci os ns get
```

Log in to OCIR with your chosen tool.

Docker example:

```bash
docker login <region-key>.ocir.io
```

Podman example:

```bash
podman login <region-key>.ocir.io
```

Use the OCI username format:

- `<tenancy-namespace>/<username>`

and an auth token as the password.

### 3. Build the custom KPO image

From the KPO source repo:

```bash
cd /home/bd/ora/oracle/karpenter-provider-oci
docker build -t <region-key>.ocir.io/<tenancy-namespace>/kpo/karpenter-provider-oci:<tag> .
```

Podman variant:

```bash
cd /home/bd/ora/oracle/karpenter-provider-oci
podman build -t <region-key>.ocir.io/<tenancy-namespace>/kpo/karpenter-provider-oci:<tag> .
```

### 4. Push the image

```bash
docker push <region-key>.ocir.io/<tenancy-namespace>/kpo/karpenter-provider-oci:<tag>
```

or:

```bash
podman push <region-key>.ocir.io/<tenancy-namespace>/kpo/karpenter-provider-oci:<tag>
```

### 5. Update Helm values in `private-oke-karpenter`

Add an explicit image override in:

- `gitops/c/kpo/values.yaml.tftpl`

Add:

```yaml
image:
  registry: <region-key>.ocir.io
  repositoryName: <tenancy-namespace>/kpo/karpenter-provider-oci
  tag: <tag>
```

If the OCIR repo is private, also add:

```yaml
imagePullSecrets:
  - name: kpo-ocir-pull
```

Then ensure the rendered file matches:

- `gitops/c/kpo/values.yaml`

### 6. Create the registry pull secret if needed

If the image is private, create the secret in namespace `karpenter`.

Docker-registry secret example:

```bash
kubectl create secret docker-registry kpo-ocir-pull \
  --namespace karpenter \
  --docker-server=<region-key>.ocir.io \
  --docker-username='<tenancy-namespace>/<username>' \
  --docker-password='<auth-token>' \
  --docker-email='<email>'
```

If the secret already exists and credentials changed, replace it safely by recreating it with the same name.

### 7. Commit and push the GitOps change

From:

- `/home/bd/gh/private-oke-karpenter`

commit:

- `gitops/c/kpo/values.yaml.tftpl`
- `gitops/c/kpo/values.yaml`

and push to the branch Argo watches.

This repo currently expects:

- `main`

### 8. Let Argo CD reconcile

Argo manages the chart application defined in:

- `gitops/c/chart.yaml`

After the Git push, Argo should roll the KPO Deployment to the new image automatically.

### 9. Verify the controller image actually changed

Check the deployed image:

```bash
kubectl -n karpenter get deploy -o jsonpath='{range .items[*]}{.metadata.name}{" -> "}{.spec.template.spec.containers[0].image}{"\n"}{end}'
```

Check pods:

```bash
kubectl -n karpenter get pods
```

Check logs:

```bash
kubectl -n karpenter logs deploy/karpenter
```

If the Deployment name differs, inspect the namespace objects first:

```bash
kubectl -n karpenter get deploy
```

### 10. Verify the functional change

After the custom controller is live, validate the intended scenario:

- create or update an `OCINodeClass` that uses:
  - `imageType: Custom`
  - `imageId` or `imageFilter`
  - `metadata.user_data` that runs `oke bootstrap`
- trigger scale-out through a `NodePool`
- confirm node provisioning succeeds

## Required Files To Change In This Repo

At minimum:

- `gitops/c/kpo/values.yaml.tftpl`
- `gitops/c/kpo/values.yaml`

Possibly also:

- `gitops/README.md`
- operational notes if you want the custom image path documented in more places

## Rollback

To roll back:

1. change the image override back to the published image settings, or remove the override
2. commit and push
3. let Argo sync

If you want a safe rollback target, record the exact prior controller image before the change.

## Practical Defaults

If you want one concrete default path for this environment, use:

- registry: private OCIR in the same OKE region
- repository: `<tenancy-namespace>/kpo/karpenter-provider-oci`
- tag style: feature + date or git SHA
- pull mode: private repo + `imagePullSecrets`

## Important Constraint

Building the image is only half the work. The cluster will not use it until:

1. the image is pushed to a reachable registry
2. the Helm values in `private-oke-karpenter` point to that image
3. Argo syncs the updated chart values
