#!/usr/bin/env node
// CDK app entrypoint for the Threshold backend.
// Instantiates one stack: ThresholdStack (VPC + ALB + Fargate + secrets + IAM).
//
// Region/account resolve from the standard CDK environment:
//   CDK_DEFAULT_ACCOUNT / CDK_DEFAULT_REGION (set by the AWS CLI profile).
// us-east-1 is pinned as the default because Nova Micro and the backend are
// validated there.

import * as cdk from 'aws-cdk-lib';
import { ThresholdStack } from '../lib/threshold-stack';

const app = new cdk.App();

new ThresholdStack(app, 'ThresholdStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION ?? 'us-east-1',
  },
  description:
    'Threshold backend: stateless Node 22 Fastify service on ECS Fargate (ARM) behind an ALB, with Secrets Manager and scoped Bedrock Nova Micro access.',
});

app.synth();
