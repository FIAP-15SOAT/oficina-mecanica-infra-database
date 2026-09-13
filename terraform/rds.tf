resource "aws_db_subnet_group" "db_subnet_group" {
  name        = local.db_subnet_group_name
  description = "Database subnet group for RDS PostgreSQL"
  subnet_ids  = data.terraform_remote_state.aws_base.outputs.private_subnet_ids

  tags = {
    Name = local.db_subnet_group_name
  }
}

resource "aws_db_instance" "rds_postgres" {
  identifier            = local.rds_identifier
  engine                = "postgres"
  engine_version        = var.db_engine_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name                     = var.db_name
  username                    = var.db_username
  manage_master_user_password = true
  port                        = var.db_port

  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.secgrp_rds.id]
  publicly_accessible    = false

  multi_az                   = var.multi_az
  backup_retention_period    = var.backup_retention_period
  skip_final_snapshot        = var.skip_final_snapshot
  deletion_protection        = false
  auto_minor_version_upgrade = true

  tags = {
    Name = local.rds_identifier
  }
}
