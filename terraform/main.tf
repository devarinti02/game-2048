terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_eks_cluster" "game-2048" {
  name     = "game-2048"
  role_arn = "arn:aws:iam::672965104327:role/eks-ec2"
  version  = "1.31"

  vpc_config {
    subnet_ids = data.aws_subnets.default.ids
  }

  access_config {
    authentication_mode = "API"
  }
}

resource "aws_eks_fargate_profile" "game_fargate_profile" {
  cluster_name           = aws_eks_cluster.game-2048.name
  fargate_profile_name   = "game-2048-fargate"
  pod_execution_role_arn = "arn:aws:iam::672965104327:role/eks-fargate"

  subnet_ids = data.aws_subnets.default.ids

  selector {
    namespace = "default"
  }

  depends_on = [
    aws_eks_cluster.game-2048
  ]
}
