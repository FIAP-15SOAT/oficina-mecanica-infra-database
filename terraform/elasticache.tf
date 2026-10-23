resource "aws_elasticache_subnet_group" "cache_subnet_group" {
  name        = local.cache_subnet_group_name
  description = "ElastiCache subnet group for Valkey"
  subnet_ids  = data.terraform_remote_state.aws_base.outputs.private_subnet_ids

  tags = {
    Name = local.cache_subnet_group_name
  }
}

ephemeral "aws_secretsmanager_random_password" "cache_auth_token" {
  password_length     = 64
  exclude_punctuation = true
}

resource "aws_elasticache_replication_group" "valkey" {
  replication_group_id       = local.cache_replication_group_id
  description                = "Valkey replication group for ${var.project_name} (${var.service_context})"
  engine                     = "valkey"
  engine_version             = "9.1"
  node_type                  = "cache.t4g.micro"
  num_cache_clusters         = 1
  automatic_failover_enabled = false
  port                       = 6379

  subnet_group_name  = aws_elasticache_subnet_group.cache_subnet_group.name
  security_group_ids = [aws_security_group.secgrp_cache.id]

  transit_encryption_enabled = true
  transit_encryption_mode    = "required"
  at_rest_encryption_enabled = true
  auth_token_wo              = ephemeral.aws_secretsmanager_random_password.cache_auth_token.random_password
  auth_token_wo_version      = 1

  apply_immediately        = true
  snapshot_retention_limit = 0

  tags = {
    Name = local.cache_replication_group_id
  }
}

resource "aws_secretsmanager_secret" "cache_auth_token" {
  name                    = local.cache_auth_token_secret_name
  description             = "ElastiCache Valkey auth token for ${var.project_name} (${var.service_context})"
  recovery_window_in_days = 0

  tags = {
    Name = local.cache_auth_token_secret_name
  }
}

resource "aws_secretsmanager_secret_version" "cache_auth_token" {
  secret_id                = aws_secretsmanager_secret.cache_auth_token.id
  secret_string_wo         = ephemeral.aws_secretsmanager_random_password.cache_auth_token.random_password
  secret_string_wo_version = 1
}
