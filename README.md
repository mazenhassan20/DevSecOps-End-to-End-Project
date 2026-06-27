# 🚀 Jerney Blog Platform — End-to-End DevSecOps & GitOps on Azure

A Gen-Z vibe blog platform (React + Node.js + PostgreSQL) shipped through a full **DevSecOps pipeline on Microsoft Azure** — from `docker-compose up` on a laptop, all the way to a TLS-secured app running on AKS behind GitOps, and finally torn back down to zero.

This README is a **complete runbook**: every command actually used, every YAML actually written, and every real error that came up along the way — kept here so it's a reference both for anyone replicating the project and for future-you when you forget how a piece fits together.

![Tech Stack](https://img.shields.io/badge/React-18-61DAFB?style=flat-square&logo=react)
![Tech Stack](https://img.shields.io/badge/Node.js-20-339933?style=flat-square&logo=node.js)
![Tech Stack](https://img.shields.io/badge/PostgreSQL-15-4169E1?style=flat-square&logo=postgresql)
![Tech Stack](https://img.shields.io/badge/Azure-AKS-0078D4?style=flat-square&logo=microsoftazure)
![Tech Stack](https://img.shields.io/badge/Terraform-IaC-7B42BC?style=flat-square&logo=terraform)
![Tech Stack](https://img.shields.io/badge/Argo_CD-GitOps-EF7B4D?style=flat-square&logo=argo)

---

## 📌 Architecture & toolchain

| Concern | Tool |
|---|---|
| Shift-left security | **Checkov** (IaC scanning), **Gitleaks** (secret scanning) |
| Containerization & CI | **Docker**, **GitHub Actions**, **Trivy** (image vulnerability scan) |
| Cloud infrastructure | **Azure Kubernetes Service (AKS)**, **Azure Container Registry (ACR)**, **Azure Key Vault** |
| Secrets management | Azure Key Vault **Secrets Store CSI Driver** |
| GitOps (CD) | **Argo CD** |
| Networking & TLS | **NGINX Ingress Controller**, **DuckDNS**, **cert-manager**, **Let's Encrypt** |

```
                          ┌────────────────────────┐
                          │      GitHub Actions      │
                          │ gitleaks → checkov →      │
                          │ build+trivy+push → write- │
                          │ back manifest → [skip ci] │
                          └───────────┬──────────────┘
                                      │ push images
                                      ▼
                          ┌────────────────────────┐
                          │  Azure Container       │
                          │  Registry (ACR)         │
                          └───────────┬──────────────┘
                                      │ pull images
                                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Azure Kubernetes Service (AKS) — namespace: blogapp                │
│                                                                       │
│   Internet ──▶ NGINX Ingress ──▶ ┌──────────┐                       │
│   (DuckDNS +     (TLS via         │ Frontend │  ClusterIP            │
│    Let's Encrypt) cert-manager)   │ (Nginx)  │                       │
│                                    └────┬─────┘                       │
│                                         │ /api                       │
│                                         ▼                            │
│                                    ┌──────────┐                       │
│                                    │ Backend  │  ClusterIP            │
│                                    │ (Node.js)│                       │
│                                    └────┬─────┘                       │
│                                         │ 5432                       │
│                                         ▼                            │
│                                    ┌──────────┐    ┌────────────────┐│
│                                    │ Postgres │◀───│ Secrets Store  ││
│                                    │ (Azure   │    │ CSI Driver     ││
│                                    │  Disk)   │    │ → Azure        ││
│                                    └──────────┘    │   Key Vault    ││
│                                                     └────────────────┘│
│   NetworkPolicies: DB accepts only from Backend, Backend only        │
│   from Frontend. All pods run non-root with dropped capabilities.    │
└─────────────────────────────────────────────────────────────────────┘
                                      ▲
                                      │ syncs desired state from Git
                          ┌────────────────────────┐
                          │        Argo CD          │
                          └────────────────────────┘
```

---

## 📁 Repository structure

```
DevSecOps-End-to-End-Project/
├── backend/                  # Node.js + Express API
├── frontend/                 # React (Vite) frontend, served by Nginx
├── deploy/                   # Legacy bare-metal (VM) deploy path — not used on AKS
├── terraform/                # Resource group, VNet, AKS, Key Vault
│   ├── provider.tf
│   ├── variables.tf
│   ├── main.tf
│   └── outputs.tf
├── k8s/                       # App manifests — this is Argo CD's sync source
│   ├── namespace.yaml
│   ├── secret-provider.yaml    # SecretProviderClass → pulls from Key Vault
│   ├── database.yaml            # StorageClass + PVC + Postgres
│   ├── backend.yaml
│   ├── frontend.yaml
│   └── network-policies.yaml
├── ingress.yaml                # NGINX Ingress + TLS for the public domain
├── cluster-issuer.yaml         # cert-manager ClusterIssuer (Let's Encrypt prod)
├── argo-application.yaml       # Argo CD Application pointing at k8s/
├── docker-compose.yml           # Local dev stack
└── .github/
    ├── workflows/ci-cd.yml      # The pipeline
    └── checkov-ci.yaml          # Checkov skip-path config
```

> Resource names used throughout this README match what was actually deployed: resource group **`blogapp-sec-rg`**, AKS cluster **`blogapp-aks`**, ACR **`blogappregistry2026`**, Key Vault **`blogapp-kv-fsx3`**, namespace **`blogapp`**. `terraform/variables.tf` defaults to `blogapp-rg` — this deployment overrode it with a local (git-ignored) `terraform.tfvars`. Swap in your own names if you fork this.

---

## ✅ Prerequisites

| Tool | Install | Verify |
|---|---|---|
| Docker + Docker Compose | https://docs.docker.com/get-docker/ | `docker --version` |
| Node.js 20+ | https://nodejs.org | `node -v` |
| Azure CLI | `curl -sL https://aka.ms/InstallAzureCLIDeb \| sudo bash` | `az --version` |
| Terraform ≥ 1.0 | https://developer.hashicorp.com/terraform/install | `terraform -v` |
| kubectl | `az aks install-cli` | `kubectl version --client` |
| Git | https://git-scm.com | `git --version` |

```bash
az login
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
```

---

## 🔑 Environment variables

`.env` at the repo root (git-ignored — never commit it):

```bash
POSTGRES_USER=blogapp_user
POSTGRES_PASSWORD=choose-a-strong-local-password
POSTGRES_DB=blogapp_db
```

On AKS, `DB_PASSWORD` comes from `blogapp-db-secret`, which is populated automatically by the Secrets Store CSI Driver — see Phase 3.

---

## Phase 1 — Local development & verification

Make sure the app runs cleanly in isolation before touching the cloud.

```bash
git clone https://github.com/mazenhassan20/DevSecOps-End-to-End-Project.git
cd DevSecOps-End-to-End-Project

cat > .env <<'EOF'
POSTGRES_USER=blogapp_user
POSTGRES_PASSWORD=choose-a-strong-local-password
POSTGRES_DB=blogapp_db
EOF

# Build and run the 3-tier architecture locally
docker compose up -d --build

# Verify running containers
docker ps
docker compose logs -f backend
```

App is reachable at `http://localhost:8085` (frontend container listens on `8080` internally, mapped to host port `8085`).

```bash
docker compose down            # stop everything
docker compose down -v         # stop and wipe the Postgres volume
docker compose exec db psql -U blogapp_user -d blogapp_db
```

---

## Phase 2 — Provision Azure infrastructure with Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

`main.tf` creates:

- **Resource group** `blogapp-sec-rg` in `East US`
- **VNet** `blogapp-vnet` (`10.0.0.0/16`) with subnet `aks-subnet` (`10.0.1.0/24`)
- **AKS cluster** `blogapp-aks` — single `Standard_B2s_v2` node, Azure CNI, Azure RBAC enabled, system-assigned managed identity, and `key_vault_secrets_provider { secret_rotation_enabled = true }` — this single block is what enables the **Azure Key Vault Secrets Provider add-on** for the cluster. You don't need to separately run `az aks enable-addons` for this — Terraform already did it.
- **Azure Key Vault** `blogapp-kv-fsx3` with an access policy for the identity that ran Terraform
- A **random 16-character database password**, generated by Terraform and stored as the Key Vault secret `postgres-password` — never written to a file in this repo

```bash
terraform output resource_group_name
terraform output kubernetes_cluster_name
terraform output key_vault_name
terraform output -raw database_password   # sensitive — only when you actually need it
```

> ⚠️ Don't hardcode `subscription_id` inside `provider.tf` if you fork this. Export it instead: `export ARM_SUBSCRIPTION_ID="<YOUR_SUBSCRIPTION_ID>"` and remove the line from the `azurerm` provider block.

---

## Phase 3 — AKS, Azure Key Vault & the CSI Driver integration

Security first: database credentials never live in Kubernetes `Secret` objects written by hand, and never sit in raw YAML in this repo. AKS mounts them straight from Azure Key Vault via the **Secrets Store CSI Driver**.

### 3.1 Connect kubectl

```bash
az aks get-credentials --resource-group blogapp-sec-rg --name blogapp-aks
kubectl get nodes
```

### 3.2 Retrieve the add-on's managed identity

When the Key Vault Secrets Provider add-on is enabled (via the `key_vault_secrets_provider` Terraform block above), AKS automatically creates a **dedicated managed identity** just for that add-on — this is *not* the same as the node/kubelet identity, and it's the one the `SecretProviderClass` needs to reference.

```bash
# Confirm the add-on is enabled and grab its identity client ID
az aks show -g blogapp-sec-rg -n blogapp-aks \
  --query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId -o tsv

# Your Azure AD tenant ID
az account show --query tenantId -o tsv
```

If for any reason the add-on isn't enabled (e.g. you're on an older cluster, or want to verify it manually), this is the equivalent CLI command Terraform runs under the hood:

```bash
az aks enable-addons --addons azure-keyvault-secrets-provider \
  --name blogapp-aks --resource-group blogapp-sec-rg
```

### 3.3 Grant that identity read access to the Key Vault

```bash
az keyvault set-policy \
  -n blogapp-kv-fsx3 \
  --secret-permissions get list \
  --spn <ADDON_IDENTITY_CLIENT_ID>
```

(`--object-id <addon-identity-object-id>` is an equivalent alternative if `--spn` doesn't resolve for you.)

### 3.4 `k8s/secret-provider.yaml` — the bridge between K8s and Key Vault

A single mismatch in `tenantId` or `userAssignedIdentityID` here and every pod that depends on it will fail to start.

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: blogapp-kv-secret-provider
  namespace: blogapp
spec:
  provider: azure
  secretObjects:
    - secretName: blogapp-db-secret
      type: Opaque
      data:
        - objectName: postgres-password
          key: POSTGRES_PASSWORD
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "<ADDON_IDENTITY_CLIENT_ID>"
    keyvaultName: "blogapp-kv-fsx3"
    tenantId: "<YOUR_AZURE_TENANT_ID>"
    objects: |
      array:
        - |
          objectName: postgres-password
          objectType: secret
```

```bash
kubectl apply -f k8s/secret-provider.yaml
```

The `secretObjects` block is the part that actually materializes a real Kubernetes `Secret` (`blogapp-db-secret`) from the Key Vault value, which is what `database.yaml` and `backend.yaml` reference via `secretKeyRef`. Without `secretObjects`, the secret would only be mounted as a file under `/mnt/secrets-store` inside the pod, not exposed as a `Secret` object usable by `env.valueFrom`.

### 3.5 How the database pod consumes it (`k8s/database.yaml`)

```yaml
containers:
  - name: postgres
    image: postgres:15-alpine
    volumeMounts:
      - name: secrets-store-inline
        mountPath: "/mnt/secrets-store"
        readOnly: true
    env:
      - name: POSTGRES_PASSWORD
        valueFrom:
          secretKeyRef:
            name: blogapp-db-secret
            key: POSTGRES_PASSWORD
volumes:
  - name: secrets-store-inline
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: "blogapp-kv-secret-provider"
```

---

## Phase 4 — Container registry & first image push

ACR isn't created by Terraform here — provisioned separately, in the same resource group, then linked to AKS for pull access.

```bash
az acr create --resource-group blogapp-sec-rg --name blogappregistry2026 --sku Basic

# let AKS pull images from it without extra credentials
az aks update --name blogapp-aks --resource-group blogapp-sec-rg --attach-acr blogappregistry2026
```

```bash
az acr login --name blogappregistry2026

docker build -t blogappregistry2026.azurecr.io/backend:init ./backend
docker push blogappregistry2026.azurecr.io/backend:init

docker build -t blogappregistry2026.azurecr.io/frontend:init ./frontend
docker push blogappregistry2026.azurecr.io/frontend:init
```

Update the `image:` lines in `k8s/backend.yaml` / `k8s/frontend.yaml` to this tag for the first manual deploy — after that, the CI/CD pipeline overwrites them automatically on every push to `main`.

---

## Phase 5 — Deploy the application manifests

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secret-provider.yaml
kubectl apply -f k8s/database.yaml
kubectl apply -f k8s/backend.yaml
kubectl apply -f k8s/frontend.yaml
kubectl apply -f k8s/network-policies.yaml
```

```bash
kubectl get pods -n blogapp
kubectl get pvc -n blogapp
kubectl get svc -n blogapp
```

---

## Phase 6 — Exposing the app: NGINX Ingress & DuckDNS

Instead of a separate `LoadBalancer` per service, a single NGINX Ingress Controller fronts everything.

```bash
# Install the NGINX Ingress Controller (cloud provider manifest)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml

# Retrieve the allocated public IP
kubectl get svc -n ingress-nginx ingress-nginx-controller -w
```

Map that `EXTERNAL-IP` to a free DuckDNS domain:

1. Create a subdomain at https://www.duckdns.org — this project uses `bloggapp.duckdns.org`
2. Point it at the IP:

```bash
curl "https://www.duckdns.org/update?domains=bloggapp&token=<TOKEN>&ip=<INGRESS_EXTERNAL_IP>"
```

---

## Phase 7 — Securing the app: cert-manager & Let's Encrypt

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml

kubectl get pods -n cert-manager   # wait until all 3 pods are Running
```

Update the email in `cluster-issuer.yaml` to your own real address before applying — Let's Encrypt rejects dummy/forbidden domains like `example.com` (see War Story #2 below):

```yaml
spec:
  acme:
    email: <your-real-email>
```

```bash
kubectl apply -f cluster-issuer.yaml
kubectl apply -f ingress.yaml

kubectl get certificate -n blogapp -w   # wait for READY: True
```

Once ready, the app is live at `https://bloggapp.duckdns.org`.

---

## Phase 8 — The secure CI/CD pipeline (GitHub Actions)

### 8.1 Service principal for the pipeline

```bash
az ad sp create-for-rbac \
  --name "blogapp-gh-actions" \
  --role Contributor \
  --scopes /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/blogapp-sec-rg \
  --sdk-auth
```

Paste the resulting JSON into a GitHub repo secret named **`AZURE_CREDENTIALS`** (`Settings → Secrets and variables → Actions`).

```bash
# the same principal also needs push rights on ACR
az role assignment create \
  --assignee <SP_APP_ID> \
  --role AcrPush \
  --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/blogapp-sec-rg/providers/Microsoft.ContainerRegistry/registries/blogappregistry2026
```

### 8.2 What `.github/workflows/ci-cd.yml` does

Triggers on push/PR to `main` touching `backend/`, `frontend/`, `terraform/`, or `k8s/`.

| Job | Tool | What it does |
|---|---|---|
| `gitleaks_scan` | Gitleaks | Scans full git history for leaked secrets/tokens |
| `security_scan` | Checkov 3.2.19 | `checkov -d . --soft-fail --skip-download --quiet --config-file ./.github/checkov-ci.yaml` |
| `build_and_push` | Docker + Trivy + ACR | Builds both images, scans each with Trivy (CRITICAL/HIGH, report-only), pushes to ACR |

`build_and_push` only runs after `security_scan` passes (`needs: security_scan`).

### 8.3 The write-back pattern (how GitOps gets its trigger)

After pushing images, the pipeline rewrites the manifest tags and commits the change back to `main` — this is the event Argo CD reacts to.

```bash
sed -i 's|blogappregistry2026.azurecr.io/backend:.*|blogappregistry2026.azurecr.io/backend:'"${GITHUB_SHA}"'|g' ./k8s/backend.yaml
sed -i 's|blogappregistry2026.azurecr.io/frontend:.*|blogappregistry2026.azurecr.io/frontend:'"${GITHUB_SHA}"'|g' ./k8s/frontend.yaml

git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git add ./k8s/*.yaml

# ⚠️ [skip ci] is mandatory here — without it, this commit re-triggers the
# pipeline, which pushes another commit, which triggers it again: an infinite loop.
git commit -m "Automated deployment: update image tags to ${GITHUB_SHA} [skip ci]"
git push origin main
```

### 8.4 `.github/checkov-ci.yaml`

```yaml
skip-path:
  - .git
```

---

## Phase 9 — GitOps with Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl get pods -n argocd -w   # wait for everything to be Running
```

```bash
# initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

# access the UI locally
kubectl port-forward svc/argocd-server -n argocd 8080:443
# open https://localhost:8080  (user: admin)
```

```bash
# link this repo's k8s/ folder to the cluster
kubectl apply -f argo-application.yaml
```

`argo-application.yaml` has `automated: { prune: true, selfHeal: true }` — drift from manual `kubectl edit`/`kubectl delete` gets reverted automatically back to whatever is committed in Git. From here on: CI pushes a new tag → Argo CD notices → Argo CD rolls it out. No manual `kubectl apply` needed for app changes.

---

## Phase 10 — Verifying everything end-to-end

```bash
kubectl get pods -n blogapp
kubectl get networkpolicy -n blogapp
kubectl get certificate -n blogapp
kubectl get application blogapp-argo -n argocd

curl -I https://bloggapp.duckdns.org
curl https://bloggapp.duckdns.org/api/health
# → {"status":"ok","message":"Jerney API is vibing ✨"}
```

---

## 🛠️ Troubleshooting & war stories

Real issues hit while building this, kept here so they don't have to be re-debugged from scratch.

### ❌ #1 — Checkov: `AssertionError: config parser should convert anything that is not a list to string`

A stale `.checkov.ymal` (typo'd filename) config file from an earlier iteration was conflicting with the new `--config-file` flag. **Fix:** delete the old config entirely and consolidate everything into one `.github/checkov-ci.yaml`, referenced explicitly.

### ❌ #2 — Checkov: `--no-guide` flag not recognized

Checkov deprecated `--no-guide` in favor of `--skip-download`. **Fix:** pin the version (`pip install checkov==3.2.19`) so a future Checkov release can't silently break the pipeline again, and use `--skip-download`.

### ❌ #3 — Key Vault CSI Driver mount failure

Backend and database pods stuck in `ContainerCreating`. `kubectl describe pod <pod-name>` showed:

```
MountVolume.SetUp failed for volume ... "Failed to fetch secret from key vault ... failed to get key vault token"
```

**Cause:** the AKS add-on's managed identity didn't have Key Vault permissions yet, and `tenantId` in `secret-provider.yaml` didn't match the actual tenant. **Fix:** ran `az keyvault set-policy` (Phase 3.3) to grant `get`/`list`, and corrected the tenant ID.

### ❌ #4 — cert-manager: ACME account registration failed

Certificate stayed `False`. `kubectl logs -n cert-manager -l app=cert-manager` showed:

```
failed to register an ACME account... contact email has forbidden domain "example.com"
```

**Cause:** Let's Encrypt blocks placeholder/example email domains. **Fix:**

```bash
# 1. put a real email in cluster-issuer.yaml, then
kubectl apply -f cluster-issuer.yaml

# 2. force-delete the stuck request to trigger a fresh attempt
kubectl delete certificaterequest blogapp-tls-secret-1 -n blogapp
```

### ❌ #5 — HTTP-01 solver pod stuck `Pending` (node pod-density limit)

The certificate challenge failed with `503 Service Temporarily Unavailable`. `kubectl get pods -n blogapp` showed cert-manager's temporary solver pod stuck `Pending`. `kubectl describe pod <solver-pod> -n blogapp` showed:

```
0/1 nodes are available: 1 Too many pods.
```

**Cause:** the single, economical `Standard_B2s_v2` node had already hit its max pod density — Argo CD's own pods were taking up the remaining headroom. **Fix (temporary resource Tetris):**

```bash
# 1. scale Argo CD down to free up scheduling room
kubectl scale deployment argocd-server -n argocd --replicas=0
kubectl scale deployment argocd-repo-server -n argocd --replicas=0
kubectl scale deployment argocd-applicationset-controller -n argocd --replicas=0

# 2. wait for the certificate to flip to READY: True
kubectl get certificate -n blogapp -w

# 3. clean up the now-finished solver pod
kubectl delete pod <solver-pod-name> -n blogapp

# 4. scale Argo CD back up
kubectl scale deployment argocd-server -n argocd --replicas=1
kubectl scale deployment argocd-repo-server -n argocd --replicas=1
kubectl scale deployment argocd-applicationset-controller -n argocd --replicas=1
```

A more permanent fix for a real deployment would be a bigger VM size or a second node, rather than this manual juggling.

### ❌ #6 — Backend can't reach the database right after a fresh deploy

The `wait-for-db` initContainer in `backend.yaml` handles the usual startup race, but if the Postgres PVC is still binding (`WaitForFirstConsumer` storage class), the DB pod itself stays `Pending` until a node claims it. Check `kubectl get pvc -n blogapp` before chasing the backend logs.

---

## 🧹 Phase 11 — Infrastructure teardown

To stop the meter, the entire resource group is destroyed — this removes AKS, ACR, the VNet, and the Key Vault in one shot, regardless of whether each was originally created by Terraform or by a plain `az` command.

```bash
# 1. remove the DuckDNS record
curl "https://www.duckdns.org/update?domains=bloggapp&token=<TOKEN>&ip=&clear=true"

# 2. (optional) remove Argo CD's own namespace before tearing down the cluster under it
kubectl delete namespace argocd

# 3. trigger asynchronous teardown of the whole resource group
az group delete --name blogapp-sec-rg --yes --no-wait

# 4. monitor progress
az group show --name blogapp-sec-rg --query properties.provisioningState
# expected: "Deleting", then the group disappears entirely

# 5. revoke the CI/CD service principal
az ad sp delete --id <SP_APP_ID>

# 6. local cleanup
docker compose down -v
docker system prune -af
```

> If you provisioned through Terraform and want your state file to match reality instead of nuking the resource group directly, `terraform destroy` from `terraform/` is the equivalent IaC-native path — but since ACR in this project was created outside Terraform, a direct `az group delete` is what actually guarantees nothing is left behind.

Confirm nothing Azure-side survives:

```bash
az group list -o table
az acr list -o table
```

**Final status:** all resources provisioned, secured, exercised end-to-end, and fully cleaned up. ✅

---

## 🛡️ Security practices implemented

- ✅ All containers run **non-root**, with `readOnlyRootFilesystem` where the runtime allows it, and `capabilities.drop: [ALL]`
- ✅ Database password **randomly generated by Terraform**, stored only in Azure Key Vault — never committed, never hardcoded
- ✅ Secrets reach pods at runtime via the **Secrets Store CSI Driver**, materialized into a real `Secret` object only inside the cluster
- ✅ **NetworkPolicies**: DB only accepts traffic from the backend; backend only from the frontend
- ✅ **Gitleaks** scans every push for accidentally committed credentials
- ✅ **Checkov** statically scans Terraform and Kubernetes manifests before any image is even built
- ✅ **Trivy** scans every built image for CRITICAL/HIGH CVEs before it's pushed
- ✅ TLS termination via **cert-manager + Let's Encrypt** — no plaintext HTTP in production
- ✅ Azure RBAC enabled on the AKS cluster
- ✅ GitOps via Argo CD: the cluster's actual state is always traceable to a Git commit, and manual drift gets self-healed away

---

## 🧾 Command cheat-sheet

```bash
# ---- Local ----
docker compose up -d --build
docker compose logs -f backend
docker compose down -v

# ---- Terraform ----
terraform init && terraform plan && terraform apply
terraform destroy

# ---- Azure ----
az login
az aks get-credentials -g blogapp-sec-rg -n blogapp-aks
az acr login --name blogappregistry2026
az aks show -g blogapp-sec-rg -n blogapp-aks --query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId -o tsv
az group delete --name blogapp-sec-rg --yes --no-wait

# ---- Kubernetes ----
kubectl get pods -n blogapp
kubectl logs -f deploy/blogapp-backend -n blogapp
kubectl describe certificate blogapp-tls-secret -n blogapp
kubectl get application blogapp-argo -n argocd
```

---

## 🙏 Credits

Originally inspired by **Abhishek Veeramalla**'s ["Jerney" DevSecOps tutorial](https://github.com/iam-veeramalla/Jerney) (AWS/EKS based). This repo reimplements the same 3-tier app and DevSecOps pipeline concept on **Microsoft Azure** instead — AKS instead of EKS, Azure Key Vault instead of native K8s secrets, ACR instead of GHCR — to see what changes (and what doesn't) when you move clouds.
