locals {
  rds_identifier               = "rds-${var.project_name}-${var.service_context}"
  db_subnet_group_name         = "dbsng-${var.project_name}-${var.service_context}"
  secgrp_rds_name              = "secgrp-rds-${var.project_name}-${var.service_context}"
  cache_replication_group_id   = "cache-${var.project_name}-${var.service_context}"
  cache_subnet_group_name      = "cachesng-${var.project_name}-${var.service_context}"
  secgrp_cache_name            = "secgrp-cache-${var.project_name}-${var.service_context}"
  cache_auth_token_secret_name = "cache-${var.project_name}-${var.service_context}-auth-token"
}
