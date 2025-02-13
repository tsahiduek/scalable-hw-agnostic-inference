export KARPENTER_NAMESPACE="kube-system"
export KARPENTER_VERSION="1.1.2"
export K8S_VERSION="1.31"

export AWS_PARTITION="aws" # if you are not using standard partitions, you may need to configure to aws-cn / aws-us-gov
export AWS_DEFAULT_REGION="eu-west-1"
export AWS_DEFAULT_REGION="us-west-2"
export CLUSTER_NAME="hw-agnostic-${AWS_DEFAULT_REGION}"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export TEMPOUT="$(mktemp)"
export ARM_AMI_ID="$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2-arm64/recommended/image_id --query Parameter.Value --output text)"
export AMD_AMI_ID="$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2/recommended/image_id --query Parameter.Value --output text)"
export GPU_AMI_ID="$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2-gpu/recommended/image_id --query Parameter.Value --output text)"
export KARPENTER_DISCOVERY_TAG=${CLUSTER_NAME}

curl -fsSL https://raw.githubusercontent.com/aws/karpenter-provider-aws/v"${KARPENTER_VERSION}"/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml  > "${TEMPOUT}" \
&& aws cloudformation deploy \
  --stack-name "Karpenter-${CLUSTER_NAME}" \
  --template-file "${TEMPOUT}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}"

# eksctl create cluster -f - <<EOF
# ---
# apiVersion: eksctl.io/v1alpha5
# kind: ClusterConfig
# metadata:
#   name: ${CLUSTER_NAME}
#   region: ${AWS_DEFAULT_REGION}
#   version: "${K8S_VERSION}"
#   tags:
#     karpenter.sh/discovery: ${CLUSTER_NAME}

# iam:
#   withOIDC: true
#   podIdentityAssociations:
#   - namespace: "${KARPENTER_NAMESPACE}"
#     serviceAccountName: karpenter
#     roleName: ${CLUSTER_NAME}-karpenter
#     permissionPolicyARNs:
#     - arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}

# iamIdentityMappings:
# - arn: "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}"
#   username: system:node:{{EC2PrivateDNSName}}
#   groups:
#   - system:bootstrappers
#   - system:nodes
#   ## If you intend to run Windows workloads, the kube-proxy group should be specified.
#   # For more information, see https://github.com/aws/karpenter/issues/5099.
#   # - eks:kube-proxy-windows

# managedNodeGroups:
# - instanceType: m5.large
#   amiFamily: AmazonLinux2
#   name: ${CLUSTER_NAME}-ng
#   desiredCapacity: 2
#   minSize: 1
#   maxSize: 10

# addons:
# - name: eks-pod-identity-agent
# EOF



curl -fsSL https://raw.githubusercontent.com/aws/karpenter-provider-aws/v"${KARPENTER_VERSION}"/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml  > "${TEMPOUT}" \
&& aws cloudformation deploy \
  --stack-name "Karpenter-${CLUSTER_NAME}" \
  --template-file "${TEMPOUT}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}"




eksctl create cluster -f - <<EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_DEFAULT_REGION}
  version: "${K8S_VERSION}"
  tags:
    karpenter.sh/discovery: ${CLUSTER_NAME}

iam:
  withOIDC: true
  serviceAccounts:
  - metadata:
      name: cloudwatch-agent
      namespace: cloudwatch-agent
    attachPolicyARNs:
    - "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"

  podIdentityAssociations:
  - namespace: "${KARPENTER_NAMESPACE}"
    serviceAccountName: karpenter
    roleName: ${CLUSTER_NAME}-karpenter
    permissionPolicyARNs:
    - arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}

iamIdentityMappings:
- arn: "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}"
  username: system:node:{{EC2PrivateDNSName}}
  groups:
  - system:bootstrappers
  - system:nodes
  ## If you intend to run Windows workloads, the kube-proxy group should be specified.
  # For more information, see https://github.com/aws/karpenter/issues/5099.
  # - eks:kube-proxy-windows

managedNodeGroups:
- instanceType: m5.large
  amiFamily: AmazonLinux2
  name: ${CLUSTER_NAME}-ng
  desiredCapacity: 2
  minSize: 1
  maxSize: 10

addons:
- name: eks-pod-identity-agent
- name: amazon-cloudwatch-observability
  # you can specify at most one of:
  attachPolicyARNs:
  - arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
EOF

export CLUSTER_ENDPOINT="$(aws eks describe-cluster --name "${CLUSTER_NAME}" --query "cluster.endpoint" --output text)"
export KARPENTER_IAM_ROLE_ARN="arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/${CLUSTER_NAME}-karpenter"
echo "${CLUSTER_ENDPOINT} ${KARPENTER_IAM_ROLE_ARN}"
export CW_ADDON_IAM_ROLE_NAME=${CLUSTER_NAME}CloudWatchAgentEks

echo "${CLUSTER_ENDPOINT} ${KARPENTER_IAM_ROLE_ARN}"

aws iam create-service-linked-role --aws-service-name spot.amazonaws.com || true


# Logout of helm registry to perform an unauthenticated pull against the public ECR
helm registry logout public.ecr.aws || true

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter --version "${KARPENTER_VERSION}" --namespace "${KARPENTER_NAMESPACE}" --create-namespace \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --wait


sed -e "s|\$KarpenterNodeRole|KarpenterNodeRole-${CLUSTER_NAME}|g" \
    -e "s|\$KarpenterDiscoveryTag|${KARPENTER_DISCOVERY_TAG}|g" \
    ./nodepools/amd-inf2-nodepool.yaml| kubectl apply -f -

sed -e "s|\$KarpenterNodeRole|KarpenterNodeRole-${CLUSTER_NAME}|g" \
    -e "s|\$KarpenterDiscoveryTag|${KARPENTER_DISCOVERY_TAG}|g" \
    ./nodepools/amd-trn-nodepool.yaml| kubectl apply -f -

sed -e "s|\$KarpenterNodeRole|KarpenterNodeRole-${CLUSTER_NAME}|g" \
    -e "s|\$KarpenterDiscoveryTag|${KARPENTER_DISCOVERY_TAG}|g" \
    ./nodepools/amd-nvidia-nodepool.yaml| kubectl apply -f -

sed -e "s|\$KarpenterNodeRole|KarpenterNodeRole-${CLUSTER_NAME}|g" \
    -e "s|\$KarpenterDiscoveryTag|${KARPENTER_DISCOVERY_TAG}|g" \
    ./nodepools/amd-nvidia-l4-nodepool.yaml| kubectl apply -f -

###

helm repo add kedacore https://kedacore.github.io/charts
helm repo update

helm install keda kedacore/keda --namespace keda --create-namespace \
  --version=2.16.1 \
  --set deploymentStrategy=Recreate \
  --set metricsService.create=true \
  --set metricsService.serviceAccountName=metrics-service \
  --set metricsService.serviceMonitor.create=true \
  --set metricsService.serviceMonitor.interval=1m \
  --set metricsService.serviceMonitor.namespace=keda \
  --set metricsService.serviceMonitor.name=keda-metrics-service

# keda-operator

export KEDA_IAM_ROLE_NAME=KedaOperator${CLUSTER_NAME}

# Create IAM role with trust policy
aws iam create-role \
    --role-name $KEDA_IAM_ROLE_NAME \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "Service": "pods.eks.amazonaws.com"
          },
          "Action": [
                "sts:AssumeRole",
                "sts:TagSession"
          ]
        }
      ]
    }'

aws eks create-pod-identity-association \
    --cluster-name $CLUSTER_NAME \
    --namespace keda \
    --service-account keda-operator \
    --role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/$KEDA_IAM_ROLE_NAME

aws iam attach-role-policy \
    --role-name $KEDA_IAM_ROLE_NAME \
    --policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess

aws iam attach-role-policy \
    --role-name $KEDA_IAM_ROLE_NAME \
    --policy-arn arn:aws:iam::aws:policy/AmazonSQSFullAccess


        # gfd:
        #   enabled: true
        # nfd:
        #   worker:
        #     tolerations:
        #       - key: nvidia.com/gpu
        #         operator: Exists
        #         effect: NoSchedule
        #       - operator: "Exists"

helm upgrade --install nvdp  https://nvidia.github.io/k8s-device-plugin/stable/nvidia-device-plugin-0.17.0.tgz \
  --repo https://nvidia.github.io/k8s-device-plugin \
  --namespace nvidia-device-plugin \
  --create-namespace \
  --set gfd.enabled=true \
  --set-json nfd.worker.tolerations='[{"key": "nvidia.com/gpu", "operator": "Exists", "effect": "NoSchedule"}, {"operator": "Exists"}]'

