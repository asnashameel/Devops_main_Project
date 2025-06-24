# Three-Tier DevOps Project for AWS EKS

This project demonstrates a complete three-tier architecture deployed on AWS EKS:
- **Frontend**: React application
- **Backend**: Node.js/Express API
- **Database**: AWS RDS PostgreSQL

## Architecture

```
Frontend (React) → Backend (Node.js) → Database (AWS RDS PostgreSQL)
```

## Project Structure

```
cloudops-project/
├── frontend/                 # React frontend application
├── backend/                  # Node.js backend API
├── k8s/                     # Kubernetes manifests
├── docker/                  # Dockerfiles
└── docs/                    # Documentation
```

## Prerequisites

- Docker Desktop
- kubectl
- AWS CLI configured
- eksctl (for EKS cluster creation)
- Node.js 18+

## Quick Start

### 1. Set up AWS RDS Database
```bash
# Setup RDS PostgreSQL database
./scripts/setup-rds.sh

# This will create:
# - RDS PostgreSQL instance
# - Security groups
# - Update ConfigMap with RDS endpoint
```

### 2. Build and Push Docker Images
```bash
# Build and push images to your registry
./scripts/build-images.sh
```

### 3. Deploy to AWS EKS
```bash
# Deploy the complete application
./scripts/deploy.sh

# Check deployment status
kubectl get all -n cloudops-demo
```

### 4. Local Development (Optional)
```bash
# For local development, set environment variables
export DB_HOST=your-rds-endpoint.region.rds.amazonaws.com
export DB_PASSWORD=your-password
docker-compose up --build
```

## Services

### Frontend
- React 18 application
- Material-UI components
- Nginx server for production

### Backend
- Node.js with Express
- REST API endpoints
- PostgreSQL integration

### Database
- AWS RDS PostgreSQL 15
- Fully managed database service
- Automated backups and monitoring
- High availability and security

## Monitoring & Observability

- Health check endpoints
- Kubernetes probes
- Service metrics

