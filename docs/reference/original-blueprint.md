# QuantumOps Platform: Project Overview & Event-Driven Architecture Blueprint

## 1. Project Description & Objectives

### Overview
As quantum computing matures, cloud-based Quantum Processing Units (QPUs) act as specialized coprocessors alongside classical compute clusters. The **QuantumOps Platform** is a production-grade infrastructure designed to bridge traditional DevOps/DataOps practices with hybrid quantum-classical workloads.

### Primary Goal
To build an automated, cost-efficient, and developer-friendly Kubernetes platform for running hybrid quantum algorithms (such as VQE and QAOA). The platform enables researchers to write standard Python and Qiskit code without embedding infrastructure decorators or managing cluster resources, while ensuring zero wasted CPU/GPU compute time during long quantum cloud queue waits.

### Core Objectives
* **Zero-Idle Compute Cost:** Eliminate idle GPU/CPU server costs while waiting in asynchronous cloud QPU queues.
* **Separation of Concerns:** Keep application code pure and free of infrastructure-specific annotations or complex distributed frame decorators.
* **Resilience via State Hydration:** Persist execution states to a external database so workloads can terminate cleanly and recover without memory loss.
* **GitOps & Declarative Security:** Manage all cluster states via GitOps and inject external QPU credentials dynamically using short-lived secrets.

---

## 2. Architectural Principles

### 1. State Hydration Pattern
Instead of maintaining long-running distributed compute nodes in memory, the system uses an ephemeral pod lifecycle. When a task submits a quantum circuit to a remote cloud provider, it serializes its current variable state into a database payload and shuts down. When the QPU finishes processing, a new pod is instantiated, reads the state from the database, and resumes execution seamlessly.

### 2. Event-Driven Execution
The system uses event routing rather than continuous polling loops inside heavy compute containers. A lightweight status tracker emits webhooks upon job completion, triggering targeted execution pods only when compute resources are actively needed.

### 3. Asynchronous Decoupling
Because physical quantum hardware queues can vary from seconds to hours, the architecture treats the external quantum cloud as a completely decoupled asynchronous service.

---

## 3. High-Level Architecture Overview

The system is organized into four logical layers:

1. **Control Plane & Secrets Management**
   * **GitHub:** Central source of truth for application code, Helm charts, and workflow configurations.
   * **ArgoCD:** GitOps controller that synchronizes the Kubernetes cluster with the repository.
   * **HashiCorp Vault:** Secure storage for third-party QPU credentials (e.g., IBM Quantum API keys) and database tokens.
   * **External Secrets Operator (ESO):** Automatically synchronizes Vault secrets into native Kubernetes secrets.

2. **State & Event Layer**
   * **Supabase (PostgreSQL):** Stores execution states, input parameters, intermediate mathematical payloads, and `qpu_job_id` references.
   * **Argo Events:** Eventbus, Webhook EventSource, and Sensor components that listen for job completion notifications and trigger dependent workflows.

3. **Ephemeral Compute Layer (Kubernetes)**
   * **Phase 1 Pod (CPU/RAM):** Runs circuit generation, matrix pre-processing, and hardware transpilation. Submits the job to the QPU and terminates.
   * **Status Tracker:** A lightweight background check (CronJob or Edge Function) that monitors the QPU queue without consuming application worker nodes.
   * **Phase 3 Pod (GPU/RAM):** Triggered by Argo Events upon completion. Hydrates state from Supabase and runs heavy classical machine learning/optimization math.

4. **External Hardware Layer**
   * **Quantum Cloud Providers:** Remote QPUs (e.g., IBM Quantum, AWS Braket, IonQ) executing physical pulse-level circuits.

---

## 4. End-to-End Operational Workflow

### Phase 1: Pre-Processing & Offloading
1. ArgoCD detects a new code release or job request and triggers an Argo Workflow.
2. A lightweight CPU pod spins up inside the cluster.
3. The pod runs the classical pre-processing code, constructs the quantum circuit, and transpiles it for target hardware topology.
4. The pod transmits the circuit to the external Quantum API and receives a unique `qpu_job_id`.
5. The pod serializes all local execution variables (matrix weights, parameters) into JSON, writes a record to Supabase with the `qpu_job_id` and a `QUEUED` status, and **terminates immediately**.

### Phase 2: Asynchronous Tracking
1. The cluster compute resources return to 0% utilization for this job.
2. A lightweight status tracker periodically queries the remote Quantum API using the stored `qpu_job_id`.
3. When the quantum cloud marks the job status as completed, the tracker updates the Supabase record to `READY` and issues a webhook payload to Argo Events.

### Phase 3: State Rehydration & Post-Processing
1. Argo Events catches the completion payload and evaluates its Sensor rules.
2. Argo Events instructs Kubernetes to spin up a specialized GPU worker pod.
3. The new GPU pod boots, receives the database record ID as an input argument, and fetches its serialized application state and raw quantum results from Supabase.
4. The GPU executes the classical machine learning or optimization algorithms using the hydrated data.
5. Metrics (circuit depth, execution latency, optimal values) are logged to observability dashboards, and the GPU pod terminates.

---

## 5. Technology Stack Summary

* **Infrastructure Orchestration:** Kubernetes, ArgoCD, OpenTofu/Terraform
* **Secrets Management:** HashiCorp Vault, External Secrets Operator
* **Workflow & Event Management:** Argo Workflows, Argo Events
* **Database & State Management:** Supabase (PostgreSQL)
* **Quantum Computing Frameworks:** Python 3.11+, Qiskit 1.x, Qiskit Runtime SDK
* **Observability:** Prometheus, Grafana
