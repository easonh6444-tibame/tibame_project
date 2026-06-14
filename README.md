# tibame_project

## Branches

| Branch | Description |
|--------|-------------|
| `main` | Latest stable state |
| `gcp` | GCP Cloud Run / GCE deployment complete |
| `ecs` | AWS ECR + ECS deployment complete |
| `ecr` | AWS ECR push via OIDC (no ECS) |
| `dev` | Development branch, merge to corresponding stage branch when stable |

## Workflow

```
dev -> feature branch -> merge to corresponding stage branch
```

## GitHub Secrets

The following secrets must be configured in repository Settings > Secrets and variables > Actions.

### All branches with CI/CD

| Secret | Description |
|--------|-------------|
| `DISCORD_WEBHOOK_URL` | Discord webhook URL for deployment notifications |

### ecr / ecs / main branches (AWS)

| Secret | Description |
|--------|-------------|
| `AWS_ROLE_ARN` | IAM Role ARN for GitHub Actions OIDC, e.g. `arn:aws:iam::ACCOUNT_ID:role/github-action` |

### gcp / main branches (GCP)

| Secret | Description |
|--------|-------------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Workload Identity Federation provider, e.g. `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL/providers/PROVIDER` |
| `GCP_SERVICE_ACCOUNT` | GCP service account email, e.g. `sa-name@project-id.iam.gserviceaccount.com` |
