provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = aws_eks_cluster.demo_cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.demo_cluster.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.demo_cluster.name, "--region", var.region]
  }
}

# Variables
variable "region" {
  default = "ap-southeast-1"
}

variable "cluster_name" {
  default = "demo-cluster"
}

variable "eks_version" {
  default = "1.31"
}

# Get AWS Account ID
data "aws_caller_identity" "current" {}

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get all subnets in the default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# KMS Key for EKS secrets encryption
resource "aws_kms_key" "eks" {
  description         = "KMS key for EKS cluster secrets encryption"
  enable_key_rotation = true
  tags = {
    Name        = "eks-kms-key"
    Environment = "dev"
  }
}

##############
# EKS Cluster
##############
resource "aws_eks_cluster" "demo_cluster" {
  name     = var.cluster_name
  version  = var.eks_version
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = data.aws_subnets.default.ids
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = {
    Name        = var.cluster_name
    Environment = "dev"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_kms_key.eks
  ]
}

####################
# EKS Node Group
####################
resource "aws_eks_node_group" "nodes" {
  cluster_name    = aws_eks_cluster.demo_cluster.name
  node_group_name = "demo-nodes"
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids      = data.aws_subnets.default.ids
  instance_types  = ["t2.micro"]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name        = "demo-nodes"
    Environment = "dev"
  }

  depends_on = [
    aws_eks_cluster.demo_cluster,
    aws_iam_role_policy_attachment.node_policy_1,
    aws_iam_role_policy_attachment.node_policy_2,
    aws_iam_role_policy_attachment.node_policy_3
  ]
}

##################
# Outputs
##################
output "cluster_name" {
  value = aws_eks_cluster.demo_cluster.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.demo_cluster.endpoint
}

output "cluster_ca_certificate" {
  value = aws_eks_cluster.demo_cluster.certificate_authority[0].data
}

output "node_group_role_arn" {
  value = aws_iam_role.node_group_role.arn
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${aws_eks_cluster.demo_cluster.name} --region ${var.region}"
}

########################
# IAM Role: EKS Cluster
########################
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "eks-cluster-role"
    Environment = "dev"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy" "eks_kms_policy" {
  name = "eks-kms-policy"
  role = aws_iam_role.eks_cluster_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.eks.arn
      }
    ]
  })
}

########################
# IAM Role: Node Group
########################
resource "aws_iam_role" "node_group_role" {
  name = "eks-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "eks-node-group-role"
    Environment = "dev"
  }
}

########################
# IAM Role: Attachment
########################
resource "aws_iam_role_policy_attachment" "node_policy_1" {
  role       = aws_iam_role.node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_policy_2" {
  role       = aws_iam_role.node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_policy_3" {
  role       = aws_iam_role.node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

########################
# aws_auth
########################
resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = aws_iam_role.node_group_role.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      }
    ])
    mapUsers = yamlencode([])
  }

  depends_on = [aws_eks_cluster.demo_cluster]
}
