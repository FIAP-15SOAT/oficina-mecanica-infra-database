# Provisional until C-20: customer-auth Lambda runs in private subnets and still reads this RDS instance
data "aws_subnet" "private" {
  for_each = toset(data.terraform_remote_state.aws_base.outputs.private_subnet_ids)
  id       = each.value
}

resource "aws_security_group" "secgrp_rds" {
  name        = local.secgrp_rds_name
  description = "Security group for RDS PostgreSQL instance"
  vpc_id      = data.terraform_remote_state.aws_base.outputs.vpc_id

  ingress {
    description     = "PostgreSQL access from EKS worker nodes"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [data.terraform_remote_state.aws_base.outputs.eks_nodes_security_group_id]
  }

  # Provisional until C-20 (decommission-customer-auth-lambda): allows the customer-auth Lambda
  # in the private subnets to reach this RDS instance before authentication moves to identity-service.
  ingress {
    description = "Provisional PostgreSQL access from private subnets for customer-auth Lambda (remove in C-20)"
    from_port   = var.db_port
    to_port     = var.db_port
    protocol    = "tcp"
    cidr_blocks = [for s in data.aws_subnet.private : s.cidr_block]
  }

  tags = {
    Name = local.secgrp_rds_name
  }
}

resource "aws_security_group" "secgrp_cache" {
  name        = local.secgrp_cache_name
  description = "Security group for ElastiCache Valkey replication group"
  vpc_id      = data.terraform_remote_state.aws_base.outputs.vpc_id

  ingress {
    description     = "Valkey TLS access from EKS worker nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [data.terraform_remote_state.aws_base.outputs.eks_nodes_security_group_id]
  }

  tags = {
    Name = local.secgrp_cache_name
  }
}
