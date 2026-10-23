output "db_instance_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.rds_postgres.id
}

output "db_instance_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.rds_postgres.arn
}

output "db_endpoint" {
  description = "RDS connection endpoint with port"
  value       = aws_db_instance.rds_postgres.endpoint
}

output "db_host" {
  description = "RDS hostname address"
  value       = aws_db_instance.rds_postgres.address
}

output "db_address" {
  description = "RDS hostname address (alias for db_host)"
  value       = aws_db_instance.rds_postgres.address
}

output "db_port" {
  description = "RDS port"
  value       = aws_db_instance.rds_postgres.port
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.rds_postgres.db_name
}

output "db_security_group_id" {
  description = "Security group ID of the RDS instance"
  value       = aws_security_group.secgrp_rds.id
}

output "db_credentials_secret_arn" {
  description = "ARN of the credentials secret managed by RDS"
  value       = aws_db_instance.rds_postgres.master_user_secret[0].secret_arn
}

output "cache_primary_endpoint" {
  description = "Primary endpoint address of the ElastiCache Valkey replication group"
  value       = aws_elasticache_replication_group.valkey.primary_endpoint_address
}

output "cache_port" {
  description = "Port of the ElastiCache Valkey replication group"
  value       = aws_elasticache_replication_group.valkey.port
}

output "cache_auth_token_secret_name" {
  description = "Name of the Secrets Manager secret storing the ElastiCache Valkey auth token"
  value       = aws_secretsmanager_secret.cache_auth_token.name
}

output "cache_security_group_id" {
  description = "Security group ID of the ElastiCache Valkey replication group"
  value       = aws_security_group.secgrp_cache.id
}
