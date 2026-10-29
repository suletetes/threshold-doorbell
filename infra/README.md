# Threshold Infrastructure (AWS CDK)

Deploys the Threshold backend to **ECS Fargate (ARM/Graviton2) behind an
Application Load Balancer** in one stack. The ALB passes WebSocket traffic
natively, which `/signaling` and `/asr/stream` require.

## What gets created

| Resource | Purpose |
|---|---|
| VPC (2 AZs, 1 NAT gateway) | Network; NAT lets the private task reach Bedrock/ECR |
| ECS Fargate service (ARM64, 0.5 vCPU / 1 GB, 1 task) | The Node 22 backend |
| Application Load Balancer (public) | HTTPS/WebSocket entry, idle timeout 605s |
| ECR image asset | Built from `../backend` on deploy |
| 3 Secrets Manager secrets | `session-secret`, `webhook-hmac-key`, `ring-client-secret` (generated) |
| CloudWatch log group `/ecs/threshold-backend` | 14-day retention |
| IAM task role | `bedrock:InvokeModel` on Nova Micro only |

## Prerequisites

- **Docker running locally** (CDK builds the ARM image during deploy)
- **AWS CLI authenticated** to account `356650046555` (`aws sts get-caller-identity`)
- **Node 18+** for the CDK CLI (Node 22 recommended; Node 20 works with an SDK warning)

## Deploy

```bash
cd infra
npm ci

# One-time per account+region: create the CDK bootstrap stack
npx cdk bootstrap

# Preview (optional)
npx cdk synth
npx cdk diff

# Deploy - builds the ARM Docker image, pushes to ECR, stands up the stack
npx cdk deploy
```

On success CDK prints outputs:

```
ThresholdStack.AlbDnsName     = ThresholdStack-xxxx.us-east-1.elb.amazonaws.com
ThresholdStack.ReadyUrl       = http://ThresholdStack-xxxx.../ready
ThresholdStack.SignalingWsUrl = ws://ThresholdStack-xxxx.../signaling
```

Verify:

```bash
curl http://<AlbDnsName>/ready
# → {"ready":true,"checks":[{"name":"config","ok":true},{"name":"tokenStore","ok":true}]}
```

## Point the Flutter app at the deployed backend

```bash
cd ../app
flutter run \
  --dart-define=DEMO=true \
  --dart-define=BACKEND_URL=http://<AlbDnsName>:80
```

(For the local two-phone demo instead, see `docs/hackathon/DEMO_RUNBOOK.md`.)

## Teardown (important for cost)

The ALB is a fixed ~$20/month charge. **Destroy the stack when you are not
actively demoing.**

```bash
cd infra
npx cdk destroy
```

## Cost at demo scale (us-east-1, approximate)

| Item | Monthly |
|---|---|
| ALB (fixed + low LCU) | ~$20 |
| NAT gateway | ~$33 |
| Fargate ARM 0.5 vCPU / 1 GB, 1 task | ~$4 |
| Secrets Manager (3 secrets) | ~$1.20 |
| CloudWatch logs + Nova Micro + ECR | ~$2 |
| **Total while running** | **~$60/mo** |

> The NAT gateway + ALB are the bulk of the cost and both bill hourly while the
> stack exists. `cdk destroy` between demos drops the cost to zero. For a purely
> local demo (no AWS), run the backend with `npm run dev` and use
> `docs/hackathon/DEMO_RUNBOOK.md` - no stack needed.

## Troubleshooting

- **`docker` errors during deploy** - Docker Desktop must be running; CDK builds
  the image locally before pushing to ECR.
- **Task fails to start, logs show `assertStrongSecret`** - the generated
  secrets satisfy this; if you overrode a secret with a short value, replace it
  with 32+ characters.
- **`/ready` returns 503** - the task is still starting or a dependency probe
  failed; check the `/ecs/threshold-backend` log group.
- **WebSocket drops after ~60s** - confirm the ALB `idle_timeout.timeout_seconds`
  attribute is 605 (set in the stack); the default 60s would cut live sessions.
- **`cdk bootstrap` assume-role warning on synth** - harmless for `synth`; real
  credentials are only needed for `deploy`.
