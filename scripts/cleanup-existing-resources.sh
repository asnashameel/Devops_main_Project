#!/bin/bash

set -e

AWS_REGION="us-west-2"
CLUSTER_NAME="cloudops-demo"

echo "========================================="
echo "Cleaning up existing conflicting resources"
echo "========================================="

# Remove existing EKS addon
echo "Removing existing EKS addon..."
aws eks delete-addon \
    --cluster-name $CLUSTER_NAME \
    --addon-name aws-ebs-csi-driver \
    --region $AWS_REGION \
    || echo "EKS addon may not exist or already deleted"

# Wait for addon to be deleted
echo "Waiting for addon deletion to complete..."
aws eks wait addon-deleted \
    --cluster-name $CLUSTER_NAME \
    --addon-name aws-ebs-csi-driver \
    --region $AWS_REGION \
    || echo "Addon deletion wait completed or timed out"

# Remove existing IAM role policy attachment
echo "Detaching IAM policy from role..."
aws iam detach-role-policy \
    --role-name "${CLUSTER_NAME}-aws-load-balancer-controller" \
    --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/${CLUSTER_NAME}-aws-load-balancer-controller" \
    || echo "Policy attachment may not exist"

# Remove existing IAM policy
echo "Deleting IAM policy..."
aws iam delete-policy \
    --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/${CLUSTER_NAME}-aws-load-balancer-controller" \
    || echo "IAM policy may not exist"

# Remove existing IAM role
echo "Deleting IAM role..."
aws iam delete-role \
    --role-name "${CLUSTER_NAME}-aws-load-balancer-controller" \
    || echo "IAM role may not exist"

# Remove Helm release if it exists
echo "Removing Helm release..."
helm uninstall aws-load-balancer-controller -n kube-system || echo "Helm release may not exist"

echo "========================================="
echo "Cleanup completed!"
echo "You can now run Terraform apply again."
echo "=========================================" 
