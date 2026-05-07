# EKS Portfolio Project Bravo

This repository contains a production-style AWS EKS platform built as a DevOps and cloud engineering portfolio project. It demonstrates how to provision a private Kubernetes environment on AWS, build and publish a containerized application, deploy it with Helm, expose it through an AWS Application Load Balancer, and operate it with a basic observability stack.

The application itself is intentionally simple: a Node.js Express service that serves a static `Hello World` page. The main value of the project is the infrastructure and delivery platform around it.

## What This Project Builds

At a high level, the project creates:

- A custom AWS network for Kubernetes workloads.
- A private Amazon EKS cluster.
- Managed EKS worker nodes.
- Amazon ECR repositories for application images, controller images, observability images, and Helm OCI charts.
- A self-hosted GitHub Actions runner inside the VPC.
- A bastion host accessible through AWS Systems Manager Session Manager.
- An internet-facing Application Load Balancer with HTTPS.
- Route 53 DNS records for the application and Grafana.
- Helm-based deployment for the Express application.
- Helm-based deployment for monitoring and logging with Prometheus, Grafana, Loki, and Promtail.

The project is designed around a private-cluster model: the EKS API endpoint is private, worker nodes run in private subnets, and deployment automation runs from inside the AWS network.

## Architecture Overview

```text
Developer
   |
   | push to main
   v
GitHub Actions
   |
   | self-hosted runner inside AWS VPC
   v
Amazon ECR <-------------------------------+
   |                                       |
   | Docker images and Helm OCI charts      |
   v                                       |
Private Amazon EKS Cluster                  |
   |                                       |
   | Helm deployments                       |
   v                                       |
Express App Pods        Observability Stack |
   |                    Prometheus          |
   |                    Grafana             |
   |                    Loki                |
   |                    Promtail            |
   v                                       |
AWS Load Balancer Controller                |
   |                                       |
   v                                       |
Application Load Balancer                   |
   |                                       |
   v                                       |
Route 53 DNS + ACM HTTPS                    |
```

## Repository Structure

```text
.
├── app/
│   ├── Dockerfile
│   ├── package.json
│   ├── server.js
│   └── public/
│       └── index.html
├── charts/
│   ├── express-app/
│   └── observability/
├── scripts/
│   ├── connect-bastion.sh
│   ├── mirror-observability-images.sh
│   ├── push-observability-chart.sh
│   └── sync-github-actions-vars.sh
├── terraform/
│   ├── environments/
│   │   └── dev/
│   └── modules/
│       ├── bastion/
│       ├── ecr/
│       ├── eks/
│       ├── elb/
│       ├── iam/
│       ├── route53/
│       ├── runner/
│       └── vpc/
└── .github/
    └── workflows/
```

## Application

The application is a minimal Express.js server:

- Runs on Node.js.
- Serves static files from `app/public`.
- Uses port `3000` by default.
- Is packaged with a Docker image based on `node:20-alpine`.
- Is deployed to Kubernetes through the `charts/express-app` Helm chart.

The application chart creates:

- A Kubernetes `Deployment`.
- A `ClusterIP` service.
- Liveness and readiness probes.
- An optional AWS Load Balancer Controller `TargetGroupBinding`.

The `TargetGroupBinding` connects the Kubernetes service directly to an AWS ALB target group created by Terraform.

## Infrastructure

Terraform is split into reusable modules under `terraform/modules` and an environment entrypoint under `terraform/environments/dev`.

### VPC

The VPC module creates a custom network layout with separate subnet tiers:

- Public subnets for the Application Load Balancer.
- Private subnets for the EKS cluster and worker nodes.
- Runner subnets for the self-hosted GitHub Actions runner and bastion.
- Database subnets reserved for future private data services.

It also creates:

- Internet Gateway.
- NAT Gateway.
- Route tables per subnet tier.
- VPC interface endpoints for services such as ECR, EKS, STS, EC2, ELB, SSM, CloudWatch Logs, and EKS Auth.
- S3 gateway endpoint.

### EKS

The EKS module provisions:

- Private EKS cluster endpoint.
- Managed EKS node group.
- KMS envelope encryption for Kubernetes secrets.
- CloudWatch control plane logging.
- EKS access entries.
- EKS managed add-ons:
  - VPC CNI
  - kube-proxy
  - CoreDNS
  - EBS CSI Driver
  - EKS Pod Identity Agent

The cluster is intentionally private. It is managed from inside the VPC through the self-hosted GitHub Actions runner or the SSM-based bastion host.

### IAM

The IAM module defines roles and policies for:

- EKS control plane.
- EKS worker nodes.
- AWS EBS CSI Driver.
- AWS Load Balancer Controller.
- EC2-based self-hosted runner.
- EC2-based bastion host.

The project uses EKS Pod Identity for Kubernetes components that need AWS permissions.

### ECR

The ECR module creates repositories for:

- The Express application image.
- AWS Load Balancer Controller image mirror.
- Express application Helm chart.
- Observability Helm chart.
- Mirrored observability stack images.

Repositories are configured with:

- Immutable image tags.
- Scan on push.
- KMS encryption.
- Lifecycle policies for old and untagged images.

### Load Balancing and DNS

Terraform provisions:

- Internet-facing Application Load Balancer.
- HTTPS listener using an existing ACM certificate.
- HTTP-to-HTTPS redirect.
- Target group for the Express app.
- Target group for Grafana.
- Route 53 records for both hostnames.

Kubernetes workloads attach to these target groups through AWS Load Balancer Controller `TargetGroupBinding` resources.

## CI/CD

The repository contains two GitHub Actions workflows.

### Application Deployment

Workflow: `.github/workflows/deploy-app.yml`

Triggered when changes are pushed to:

- `app/**`
- `charts/express-app/**`
- `.github/workflows/deploy-app.yml`

Main steps:

1. Build the Express app Docker image.
2. Push the image to Amazon ECR.
3. Mirror the AWS Load Balancer Controller image into private ECR.
4. Package the Express app Helm chart.
5. Push the Helm chart to ECR as an OCI artifact.
6. Configure `kubectl` for the private EKS cluster.
7. Install or upgrade the AWS Load Balancer Controller.
8. Deploy the application Helm release.

### Observability Deployment

Workflow: `.github/workflows/deploy-observability.yml`

Triggered when changes are pushed to:

- `charts/observability/**`

Main steps:

1. Build Helm chart dependencies.
2. Mirror public observability container images into private ECR.
3. Package the observability Helm chart.
4. Push the chart to ECR as an OCI artifact.
5. Configure `kubectl` for the private EKS cluster.
6. Deploy the observability stack.

The image mirroring step is important because private cluster workloads should not depend on direct public image pulls.

## Observability Stack

The observability chart is located in `charts/observability`.

It uses Helm dependencies for:

- `kube-prometheus-stack`
- `loki`
- `promtail`

It deploys:

- Prometheus for metrics collection.
- Grafana for dashboards.
- Loki for log storage.
- Promtail for log shipping.
- A custom Grafana dashboard ConfigMap.
- A `gp3` encrypted EBS-backed storage class.
- Optional `TargetGroupBinding` for Grafana access through the shared ALB.

## Helper Scripts

The `scripts` directory contains operational helpers:

- `connect-bastion.sh` starts an SSM session into the bastion host.
- `sync-github-actions-vars.sh` reads Terraform outputs and syncs them into GitHub Actions repository variables.
- `mirror-observability-images.sh` renders the observability chart, discovers public images, and mirrors them into ECR.
- `push-observability-chart.sh` packages and pushes the observability Helm chart to ECR as an OCI artifact.

## Prerequisites

To deploy this project, the local machine or automation environment needs:

- AWS CLI configured with permissions to create the required infrastructure.
- Terraform `>= 1.9.0`.
- Docker.
- Helm.
- kubectl.
- jq.
- curl.
- A public Route 53 hosted zone.
- An issued ACM certificate matching the configured application domain.
- A GitHub repository where the self-hosted runner can register.
- A GitHub Personal Access Token stored in SSM Parameter Store for runner registration.

## Deployment Flow

The expected flow is:

1. Configure Terraform variables for the environment.
2. Apply Terraform to provision AWS infrastructure.
3. Store the GitHub runner registration token in SSM Parameter Store.
4. Sync Terraform outputs into GitHub Actions repository variables.
5. Push application or chart changes to `main`.
6. GitHub Actions builds, packages, and deploys the workloads from the self-hosted runner.

Example Terraform commands:

```bash
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
```

After Terraform creates the infrastructure, the `github_actions_variables` output can be synced into the GitHub repository:

```bash
scripts/sync-github-actions-vars.sh
```

The Terraform output also prints helper commands for:

- Seeding the GitHub PAT into SSM.
- Starting an SSM session into the runner for debugging.

## Security Notes

This project intentionally uses a private EKS control plane. The cluster API is not publicly accessible. Administrative access is provided through AWS-native identity and network paths:

- EKS access entries.
- IAM roles.
- SSM Session Manager.
- Private VPC connectivity.
- A self-hosted GitHub Actions runner deployed inside the VPC.

The project also uses:

- KMS encryption for EKS secrets.
- Encrypted EBS volumes.
- ECR image scanning.
- Private ECR mirrors for runtime images.
- HTTPS exposure through ALB and ACM.

## Technologies Used

- AWS
- Amazon EKS
- Kubernetes
- Terraform
- Helm
- Docker
- GitHub Actions
- Self-hosted GitHub Actions Runner
- Amazon ECR
- AWS IAM
- EKS Pod Identity
- AWS VPC
- VPC Endpoints
- AWS Systems Manager Session Manager
- Amazon EC2
- Application Load Balancer
- AWS Load Balancer Controller
- Route 53
- ACM
- KMS
- CloudWatch
- EBS CSI Driver
- Node.js
- Express.js
- Prometheus
- Grafana
- Loki
- Promtail
- Bash

## Project Purpose

This project demonstrates practical DevOps and cloud platform engineering skills:

- Designing AWS infrastructure with Terraform modules.
- Building a private Kubernetes platform on EKS.
- Deploying applications with Docker and Helm.
- Automating delivery through GitHub Actions.
- Operating private infrastructure with SSM and internal runners.
- Exposing Kubernetes workloads through ALB target groups.
- Adding metrics, logs, dashboards, and persistent storage.
- Managing container image and Helm chart distribution through ECR.

It shows the full lifecycle of a cloud-native workload: infrastructure provisioning, secure access, CI/CD automation, Kubernetes deployment, ingress, DNS, TLS, and observability.
