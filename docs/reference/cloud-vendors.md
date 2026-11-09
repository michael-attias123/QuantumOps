# Cloud vendor comparison for QuantumOps (as of 2026-11-05)

> **Decision (2026-11-05): stay with Oracle Cloud Always Free** (single A1 node, 2 OCPU / 12 GB; see
> [ADR 0002](../adr/0002-oci-always-free-and-tailscale.md) and [ADR 0008](../adr/0008-single-node-a1-cluster.md)).
> Hetzner CAX31 (~€21/month) is the fallback if the free tier becomes unusable; paid options need explicit approval.
>
> **Free Trial (2026-11-08):** new OCI accounts also get **$300 of credits for 30 days**. We use them only as a
> disposable burst layer (mainly a GPU test for L3), deleted by trial day 27; see
> [ADR 0010](../adr/0010-oci-trial-burst-layer.md).

**Method.** All figures come from web search results. **WebFetch was blocked** for vendor sites in this session (docs.oracle.com failed DNS, and cloud.google.com returned only a page title), so no official page was read directly. Figures marked **(3P)** come from third-party price aggregators and need checking against the vendor calculator. A month is taken as 730 h. Prices are list, on-demand, for US regions unless noted otherwise.

## Summary table

| Vendor | Always-free compute | Managed K8s control plane | ~4 vCPU / 16 GB always-on, $/mo | Cheapest GPU $/h; scale-to-zero | KMS / secrets for Vault | Free Postgres / object storage | Quantum | $0 feasible? |
|---|---|---|---|---|---|---|---|---|
| **AWS** | None always-free; Free plan with up to $200 credit for ≤6 months | EKS $0.10/h (~$73) | t4g.xlarge (ARM) ~$98; m7g.xlarge ~$119 | g4dn.xlarge T4 $0.526; g6.xlarge L4 $0.80; Karpenter/CA to 0 | KMS $1/key + 20k req free; `awskms` seal ✔ | RDS/S3 only via credits | **Braket**: 1 h/mo simulator, first 12 months | No (6 months) |
| **Google Cloud** | e2-micro (2 shared vCPU, 1 GB, x86) in 3 US regions; $300 / 90 days | GKE $0.10/h, **$74.40/mo credit covers 1 zonal or Autopilot cluster** | t2a-standard-4 (ARM) ~$112; spot ~$36; 1-yr CUD ~$59 | T4 $0.35/GPU-h + VM; GKE pool min 0 ✔ | Cloud KMS (paid, low); `gcpckms` ✔; Secret Manager 6 versions free | 5 GB GCS; no free Cloud SQL | No public QPU (Willow by proposal only) | Control plane only; nodes cost money |
| **Azure** | B1s / B2pts v2 (ARM) / B2ats v2, 750 h/mo **for 12 months**; $200 / 30 days | AKS Free tier $0; Standard $0.10/h | B4ps v2 (ARM) ~$98 | NC4as T4 v3 $0.526; user pool to 0 ✔ | Key Vault ~$0.03/10k ops; `azurekeyvault` ✔ | PG Flexible B1ms free 12 months | **Azure Quantum**: $500 credit per provider | 12 months only |
| **Oracle OCI** | **A1 ARM: 2 OCPU / 12 GB (cut from 4/24 in June 2026)** + 2 AMD micro | OKE Basic $0; Enhanced $0.10/h (cap $74.40) | A1 4 OCPU / 16 GB ≈ $47 list, or ≈ $19 above the free allowance | A10 ~$2.00 (no T4/L4 found) | OCI Vault: software keys free, 20 HSM key versions free; `ocikms` ✔ | Autonomous DB (Oracle, not PG) ×2; 10–20 GB object storage | None | **Yes** (2 OCPU / 12 GB) |
| **IBM Cloud** | Lite plans (40+ services); no always-free VM | IKS: one free single-worker cluster (specs not verified) | Not verified | Not verified | Key Protect (free tier possibly ended Jan 2025); **no OSS Vault seal** | Lite DBs; COS Lite | **IBM Quantum** Open Plan: 10 min / 28 days | Partly; not for this stack |
| **Hetzner** | None | None (k3s on VM) | **CAX31 ARM 8 vCPU / 16 GB €20.99**; CX43 x86 €15.99 (often sold out) | No cloud GPU | None (use external KMS) | Object storage €4.99 for 1 TB | None | No; cheapest paid |
| **DigitalOcean** | $200 trial credit | DOKS $0 (HA +$40/mo) | Premium AMD 4 / 16 ~$84 (2023 price) | RTX 4000 Ada $0.76, per-second billing | None native | Spaces $5 (250 GB) | None | No |
| **GPU add-on: Modal** | **$30/mo free credits** | n/a (serverless) | n/a | T4 ~$0.59, L4 ~$0.80; per second, true scale-to-zero | n/a | n/a | n/a | GPU only |

Vault seal types confirmed in docs and source: awskms, gcpckms, azurekeyvault, ocikms, alicloudkms, transit; pkcs11 is Enterprise-only ([Vault seal source](https://github.com/hashicorp/vault/blob/v1.4.6/command/server/seal/server_seal.go), [ocikms docs](https://developer.hashicorp.com/vault/docs/configuration/seal/ocikms)).

---

## AWS
- **Free tier.** Since July 2025, new accounts get $100 in credit plus up to $100 more for completing activities. The Free plan ends after 6 months or when the credit runs out, whichever comes first. Separately, more than 30 services keep always-free monthly limits, but EC2 and RDS draw down the credit. There is no always-free VM. [AWS What's New](https://aws.amazon.com/about-aws/whats-new/2025/07/aws-free-tier-credits-month-free-plan/), [AWS blog](https://aws.amazon.com/blogs/aws/aws-free-tier-update-new-customers-can-get-started-and-explore-aws-with-up-to-200-in-credits).
- **K8s.** EKS costs $0.10 per cluster-hour (~$73/mo). Extended support costs $0.60/h. Auto Mode adds a per-instance fee. [EKS pricing](https://aws.amazon.com/eks/pricing/), [cloudburn (3P)](https://cloudburn.io/blog/amazon-eks-pricing).
- **Node.** t4g.xlarge (ARM, 4 vCPU / 16 GiB) is $0.1344/h, about $98/mo. m7g.xlarge is $0.1632/h, about $119/mo. [Holori (3P)](https://calculator.holori.com/aws/ec2/t4g.xlarge/us-east-1), [DoiT (3P)](https://www.doit.com/compute/spot/us-east-1/m7g.xlarge). Spot capacity is roughly 50–60% cheaper, and Savings Plans run about 30–40% cheaper (general knowledge, not verified).
- **GPU.** g4dn.xlarge (T4) is $0.526/h, with spot around $0.21. g6.xlarge (L4) is $0.8048/h. [DevZero (3P)](https://www.devzero.io/instances/aws/g4dn.xlarge), [DoiT (3P)](https://www.doit.com/compute/spot/us-east-1/g6.xlarge). New accounts usually start with a **G-instance vCPU quota of 0**, and increases can be denied for new accounts. [re:Post](https://repost.aws/questions/QUxBIRsixkTneUqAemd6QVjw/good-question-this-is-a-common-issue-when-you-try-to-launch-gpu-instances-like-g-4-dn-xlarge-in-aws-but-get-an-error-such-as-instance-limit-exceeded-you-do-not-have-sufficient-quota), [AWS KC](https://repost.aws/knowledge-center/ec2-on-demand-instance-vcpu-increase). Karpenter or Cluster Autoscaler can scale GPU nodes to zero.
- **Secrets/KMS.** KMS costs $1 per key per month, with 20,000 requests a month free. Secrets Manager costs $0.40 per secret per month plus $0.05 per 10k calls. [KMS pricing](https://aws.amazon.com/kms/pricing/), [Secrets Manager pricing](https://aws.amazon.com/secrets-manager/pricing/). The `awskms` seal is mature, and **it works from any host, so $1/mo buys auto-unseal for a k3s cluster anywhere.**
- **Storage/DB.** S3, RDS and ECR are free only through credits or limited free tiers. Internet egress has 100 GB/mo free. [CloudZero](https://www.cloudzero.com/blog/aws-egress-costs).
- **Quantum.** Amazon Braket includes 1 h/mo of managed simulator time for the first 12 months. QPU time is paid. [Braket pricing](https://aws.amazon.com/braket/pricing/).
- **OpenTofu.** `hashicorp/aws` is the most mature provider. **Gotchas:** credit expiry, GPU quota of zero on new accounts, and the EKS fee.

## Google Cloud
- **Free tier.** New customers get $300 in credit for 90 days. The always-free tier includes one e2-micro (2 shared vCPU / 1 GB, x86) in us-west1, us-central1 or us-east1, 5 GB-month of Cloud Storage (US regional), 0.5 GB of Artifact Registry, and 6 Secret Manager versions. [cloud.google.com/free](https://cloud.google.com/free-trial/), [agentdeals (3P)](https://agentdeals.dev/gcp-free-tier-2026).
- **K8s.** GKE charges $0.10 per cluster-hour, but **$74.40 a month in free-tier credit per billing account covers one zonal or Autopilot cluster**. The credit does not cover nodes or regional clusters. [GKE pricing](https://cloud.google.com/anthos/pricing?authuser=3), [Finout (3P)](https://www.finout.io/blog/gke-pricing-tiers). The e2-micro is too small to serve as a node for this stack.
- **Node.** t2a-standard-4 (ARM, 4 vCPU / 16 GB) is $0.154/h, about $112/mo. Spot is about $36/mo and a 1-year CUD is $0.0805/h, about $59/mo. [Holori (3P)](https://calculator.holori.com/gcp/vm/t2a-standard-4), [cloudprice (3P)](https://cloudprice.net/gcp/compute/instances/t2a-standard-4).
- **GPU.** The T4 costs $0.35 per GPU-hour plus the VM. G2 (L4) pricing bundles the GPU into the machine price. [GPU pricing](https://cloud.google.com/compute/gpus-pricing?hl=es). GKE GPU node pools support `--min-nodes 0`, and Autopilot bills GPU pods per second. [community guide](https://apxml.com/courses/advanced-ai-infrastructure-design-optimization/chapter-3-advanced-kubernetes-orchestration/practice-gpu-autoscaling-group). The default GPU quota is usually 0 for trial accounts (not verified).
- **Secrets/KMS.** Cloud KMS charges per key version and per operation. The figure of about $0.06 per key version per month was not confirmed. [KMS pricing](https://cloud.google.com/kms/pricing). The `gcpckms` seal is supported, and Secret Manager has 6 free versions.
- **DB.** Cloud SQL has no free tier, so Supabase or Neon would stay.
- **Quantum.** There is no public cloud QPU. Willow is available only through a selective early-access proposal program (2026) and the UK NQCC route. [Quantum Insider](https://thequantuminsider.com/2026/03/28/google-opens-early-access-to-willow-quantum-processor-invites-experimental-proposals/embed/), [NQCC](https://www.nqcc.ac.uk/?p=26444).
- **OpenTofu.** `hashicorp/google` is very mature. **Gotchas:** a static IP consumes credit, and one source says default buckets need billing linked since Feb 2026 (unverified).

## Microsoft Azure
- **Free tier.** $200 in credit for 30 days. For 12 months after that, 750 h/mo each of B1s, B2pts v2 (ARM, 2 vCPU / 1 GB) and B2ats v2. One page labels the VMs "Always", but Microsoft Learn says 12 months. [Azure free](https://azure.microsoft.com/en-us/free/), [Learn](https://learn.microsoft.com/azure/cost-management-billing/manage/create-free-services).
- **K8s.** The AKS Free tier has no control-plane charge but also no financially backed SLA. The Standard tier costs $0.10/h. [Learn](https://learn.microsoft.com/azure/architecture/aws-professional/eks-to-aks/cost-management). User node pools can scale to 0. [Learn](https://learn.microsoft.com/en-us/training/modules/aks-optimize-compute-costs/2-node-pools).
- **Node.** B4ps v2 (ARM, 4 vCPU / 16 GB) is $0.134/h, about $98/mo. B4pls v2 (8 GB) is about $87. [cloudoptimo (3P)](https://costcalc.cloudoptimo.com/azure-pricing-calculator/vm/Standard-B4ps-v2), [economize (3P)](https://www.economize.cloud/resources/azure/pricing/virtual-machine/b4plsv2/).
- **GPU.** NC4as T4 v3 is $0.526/h, with spot around $0.149. [Vantage (3P)](https://instances.vantage.sh/azure/vm/nc4ast4-v3). Free and trial subscriptions generally have no GPU quota (not verified).
- **Secrets/KMS.** Key Vault Standard charges $0.03 per 10k operations. [Infisical (3P)](https://infisical.com/blog/secrets-manager-pricing). The `azurekeyvault` seal is supported.
- **DB/storage.** Azure Database for PostgreSQL Flexible Server B1ms is free for 12 months, then about $14.60/mo. [Bytebase (3P)](https://www.bytebase.com/blog/postgres-hosting-options-pricing-comparison/). Egress has 100 GB/mo free (3P).
- **Quantum.** Azure Quantum gives $500 in credit per participating provider (IonQ, Quantinuum, PASQAL, Rigetti), and up to $10k more by application. [Learn pricing](https://learn.microsoft.com/azure/quantum/pricing), [credits FAQ](https://learn.microsoft.com/azure/quantum/credits-faq).
- **OpenTofu.** `azurerm` is mature but changes often between versions. **Gotcha:** the free offer is effectively time-limited.

## Oracle Cloud (OCI)
- **Free tier, A1 cut verified by multiple sources.** The Always Free A1 allowance is now **1,500 OCPU-hours and 9,000 GB-hours a month, which equals 2 OCPU / 12 GB** (down from 3,000 / 18,000, or 4 / 24). It took effect around **2026-06-15** with no public announcement. Tenancies over the limit had to reduce by 2026-08-18, otherwise instances are stopped. [InfoQ](https://www.infoq.com/news/2026/07/oracle-cloud-free-tier-limits/), [linuxiac](https://linuxiac.com/oracle-quietly-cuts-free-tier-ampere-a1-resources-in-half/), [terminalbytes](https://terminalbytes.com/oracle-cloud-free-tier-changes-2026/), [Oracle forum](https://community.oracle.com/customerconnect/discussion/974451/always-free-a1-disabled-need-re-enable-to-resize-4-ocpu-24gb-to-2-ocpu-12gb), [HN](https://hn.svelte.dev/item/49183750). **Unclear:** whether PAYG tenancies keep 4/24 (the docs say "all tenancies", while support emails say free-only). The free tier also includes 200 GB of block volume and 2 AMD micro VMs. The official page could not be fetched. [Always Free Resources](https://docs.oracle.com/en-us/iaas/Content/FreeTier/resourceref.htm). There is also a $300 / 30-day trial.
- **K8s.** OKE Basic clusters have **no control-plane fee**. Enhanced clusters cost $0.10/h, capped at $74.40/mo. New clusters default to Enhanced. [OKE pricing](https://www.oracle.com/cloud/cloud-native/kubernetes-engine/pricing). OKE Basic can use Always Free A1 nodes.
- **Node.** A1 lists at $0.01 per OCPU-hour and $0.0015 per GB-hour (2021 launch rates, not re-verified). [Arm blog](https://developer.arm.com/community/arm-community-blogs/b/servers-and-cloud-computing-blog/posts/oracle-cloud-infrastructure-arm-based-a1). That makes 4 OCPU / 16 GB ≈ $47/mo at list, or ≈ $19/mo for the portion above a 2/12 free allowance, if that allowance applies on PAYG.
- **GPU.** VM.GPU.A10.1 costs about $2.00/h (Oracle blog), with a third-party figure of about $1.27. [Oracle blog](https://blogs.oracle.com/cloud-infrastructure/post/graphics-rendering-nvidia-a10-gpu-oci). There is no cheap T4/L4 tier, and GPU limits require a paid account and a limit request (anecdotal).
- **Secrets/KMS.** OCI Vault virtual vaults are free tier: software keys are free and the first 20 HSM key versions are free. Secrets have a free allowance of 150 (3P). [Oracle JP blog](https://blogs.oracle.com/oracle4engineer/post/ja-key-mgmt-key-to-protecting-data), [fitgap (3P)](https://us.fitgap.com/products/019648/oracle-cloud-infrastructure-vault). **The `ocikms` seal is supported** and can authenticate with an instance principal, but forum threads report SDK and config friction. [HashiCorp](https://developer.hashicorp.com/vault/docs/configuration/seal/ocikms), [discuss](https://discuss.hashicorp.com/t/oci-kms-unseal-working-or-not/47471).
- **Storage/DB.** Object storage is 10 GB Standard, or 20 GB including Infrequent Access (sources conflict). There are 2 Autonomous Databases of 20 GB each, which run **Oracle, not Postgres**. Egress has **10 TB/mo free**. [cleverence (3P)](https://www.cleverence.com/articles/oracle-documentation/oracle-cloud-infrastructure-free-tier-4827/), [issoh (3P)](https://www.issoh.co.jp/tech/details/17531/). OCIR is the container registry.
- **Quantum.** None.
- **OpenTofu.** `oracle/oci` is mature and vendor-maintained but verbose. **Gotchas:** idle reclamation (7 days with 95th-percentile CPU, network and A1 memory all under 20%; converting to PAYG avoids it) [51sec](https://www.51sec.org/2023/05/16/oracle-cloud-cleaning-up-idle-compute-instances-how-to-keep-it/), [oracommit](https://oracommit.blogspot.com/2026/02/understanding-oci-always-free-compute.html); "out of capacity" errors for A1 in popular regions; and many reports of accounts terminated without notice. [Oracle forum](https://community.oracle.com/customerconnect/discussion/727726/account-was-terminated-with-0-warning-and-no-explanations-whatsoever).

## IBM Cloud
- **Free tier.** More than 40 Lite services that never expire, a $200 / 30-day credit, and a free single-worker IKS cluster (specs and current availability not verified). The TRYCONTAINERS promo expired on 30 June 2026 (one localized page says 31 Dec). [IBM free K8s](https://www.ibm.com/products/cloud/free/kubernetes). Basic support has been AI and docs only since Jan 2026. [The Register](https://www.theregister.com/2025/09/04/ibm_cloud_basic_support_changes/).
- **KMS.** Key Protect historically had 20 free keys, but the free tier was reportedly removed in Jan 2025 (3P). **Open-source Vault has no Key Protect seal.** IBM's own Vault guidance uses HPCS with PKCS#11, which is Vault Enterprise. [IBM tutorial](https://developer.ibm.com/tutorials/integrate-enterprise-vault-ibm-cloud-hyper-protect-crypto-services/).
- **Quantum.** This is IBM's strength. The IBM Quantum Open Plan gives 10 min of QPU time per rolling 28 days, and a 2026 opt-in promotion adds 180 min over 12 months. It is usable from any cloud through Qiskit Runtime. [IBM plans](https://quantum.cloud.ibm.com/docs/guides/plans-overview), [IBM blog](https://www.ibm.com/quantum/blog/open-plan-updates).
- **OpenTofu.** `IBM-Cloud/ibm` is official but less widely used. IBM Cloud is not a good host for this stack; use **IBM Quantum** separately.

## Hetzner (cheapest paid)
- On 2026-06-15, prices rose for new orders and rescales (cost-optimized lines by +30–38%). New EU prices: **CAX31 (ARM, 8 vCPU / 16 GB) €20.99/mo**, CAX21 (4 / 8) €10.49, CX43 (x86, 8 / 16) €15.99. Reports in Aug 2026 said cost-optimized plans were often **"not available"**. [Northflank](https://northflank.com/blog/hetzner-cloud-server-price-increases), [trackvps](https://trackvps.com/hetzner-price-increase), [hostmath](https://hostmath.dev/guides/hetzner-price-increase-2026).
- Hetzner has no managed K8s, KMS, Postgres or cloud GPU. Object storage costs €4.99/mo for 1 TB of storage plus 1 TB of egress. [egresscost](https://egresscost.com/hetzner). Each server includes 20 TB of traffic (general knowledge). The `hetznercloud/hcloud` provider is mature, and k3s via kube-hetzner is popular.

## DigitalOcean
- DOKS has a free control plane, with HA at +$40/mo. [DO pricing](https://digitalocean.com/pricing). The Premium AMD 4 vCPU / 16 GB Droplet was $84/mo in 2023 docs (not re-verified). [DO docs](https://docs.digitalocean.com/notes/2023/new-basic-droplet-premium-cpu-plans). GPU Droplets bill per second, with RTX 4000 Ada at $0.76/h (pricing effective 2026-08-01). [DO GPU](https://www.digitalocean.com/pricing/gpu-droplets). Spaces costs $5 for 250 GB plus 1 TB of transfer. There is no KMS. It offers good UX but is about 4× Hetzner's price for this node.

## GPU add-ons (scale-to-zero)
- **Modal:** the free Starter plan includes $30/mo in credit. T4 is $0.000164/s (~$0.59/h) and L4 is ~$0.80/h, billed per second with true scale-to-zero. That is about 50 free T4-hours a month. [morphllm (3P)](https://www.morphllm.com/modal-pricing).
- **RunPod:** serverless L4 is roughly $0.39–0.69/h (sources conflict), there is no free plan, and there is about $10 of starting credit. [RunPod](https://www.runpod.io/articles/comparison/runpod-vs-modal).
- **Kaggle (current plan):** about 30 GPU-h a week on T4×2 or P100, with 12 h sessions. The quota is community-reported and floats. [gpuperhour](https://gpuperhour.com/blog/free-cloud-gpus-and-credits). CUDA-Q and cuStateVec run on T4.

## Shared $0 building blocks
Several pieces stay the same in every option:
- **Postgres:** Supabase Free (500 MB, pauses when inactive) or Neon (0.5 GB per project, 100 CU-h). [Neon](https://neon.com/faqs/best-free-low-cost-managed-postgres-services).
- **Object storage:** Cloudflare R2, with 10 GB free and free egress. [Upstash](https://upstash.com/kb/cloudflare-r2-pricing-in-2026-storage-operations-and-real-monthly-bills).
- **Registry and network:** GHCR and Tailscale.

---

## Fit for QuantumOps

**(a) $0 option: OCI Always Free A1 (2 OCPU / 12 GB) running k3s. Cost: $0/mo.**
- **k3s placement:** k3s runs on a single A1 VM, or on OKE Basic with A1 nodes (no control-plane fee, but OKE system pods use some of the 12 GB).
- **Stack fit:** 12 GB is below the 12–16 GB target. Shrink the stack by using Loki in single-binary mode, Prometheus with short retention, one Argo Events NATS replica, and Vault standalone. Expect about 6 GB for the platform and about 5 GB for workloads.
- **Vault:** auto-unseal through `ocikms` with a free software key in a virtual vault. OCI Vault secrets can serve as an ESO backend alternative.
- **Storage:** OpenTofu state and Vault snapshots go to OCI Object Storage (free) or R2. Keep Supabase and GHCR.
- **GPU:** use Kaggle for batch jobs and Modal's $30 credit for scale-to-zero CUDA-Q QEC and Aer-GPU runs.
- **Quantum:** IBM Quantum Open Plan.
- **Risks:** idle reclamation (the platform's memory use should keep it above the threshold, but upgrading to PAYG with a $1 budget alarm is the safer choice), A1 capacity errors, the risk of account termination, and further silent cuts. Keep everything in OpenTofu and GitOps, with off-cloud backups to R2, so the cluster can be rebuilt quickly.

**(b) Cheapest paid option: Hetzner CAX31 (ARM, 8 vCPU / 16 GB) running k3s. Cost: about €21–26/mo (~$24–30).**
- **Compute:** it meets the full 4 vCPU / 16 GB target with headroom. Add €4.99 for object storage, or use R2 for free.
- **Vault:** Hetzner has no KMS, so use the **AWS KMS `awskms` seal for about $1/mo**, or the free OCI KMS through `ocikms` with API-key authentication, run cross-cloud over the internet.
- **Unchanged:** GPU, Postgres and quantum stay as in (a).
- **Alternative:** an OCI PAYG A1 VM with 4 OCPU / 16 GB costs about $19–47/mo depending on whether the free allowance is honoured on PAYG. It is cheaper but carries the OCI account risk.
- **Watch:** Hetzner stock shortages and the pace of its 2026 price increases.

**(c) Best experience option: GKE on Google Cloud. Cost: about $60–125/mo plus per-second GPU time.**
- **Cluster:** one zonal GKE Standard cluster, with the fee covered by the $74.40 credit. Run one t2a-standard-4 node on a 1-year CUD (~$59) or on demand (~$112), or use Autopilot.
- **GPU:** a T4 or L4 node pool with min 0 nodes. Kaggle is replaced by vendor GPUs at about $0.35/h for the T4 plus the VM (roughly $0.5–0.6/h total), once GPU quota is granted.
- **Vault and secrets:** Vault unseals with `gcpckms` through Workload Identity, and ESO can read from Secret Manager.
- **Storage and registry:** GCS for state and snapshots, and Artifact Registry or GHCR.
- **Optional extras:** keep Supabase, or move to Cloud SQL for about $10+ per month.
- **Quantum:** GCP has no QPU, so keep IBM Quantum (or add Braket and Azure Quantum credits). The $300 / 90-day credit covers about the first three months.
- **AWS equivalent:** EKS ($73) plus t4g.xlarge ($98) is about $171/mo, so it costs more. Choose it only for Braket integration.

## Facts not verified
- Whether OCI PAYG tenancies keep 4 OCPU / 24 GB of A1. OCI's current A1 paid rates, object storage free size (10 vs 20 GB), and the 150 free secrets. docs.oracle.com could not be fetched.
- The current CPU threshold for OCI idle reclamation (20% is the latest reported figure).
- GCP Cloud KMS per-key price, the default GPU quota on new GCP and Azure accounts, the 1 GB free egress on GCP, and g2-standard-4 pricing.
- IBM IKS free cluster specs and availability in Nov 2026, Key Protect's current free tier, and IBM VM pricing.
- DigitalOcean's current 4 vCPU / 16 GB Droplet price, RunPod's T4 and L4 serverless rates, and Kaggle's official GPU quota.
- Spot and Savings Plan percentages for AWS and Azure (stated from general knowledge).
- Every aggregator (3P) price should be checked against the vendor calculators before committing.
