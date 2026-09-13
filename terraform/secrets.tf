resource "aws_secretsmanager_secret_rotation" "db_credentials" {
  secret_id        = aws_db_instance.rds_postgres.master_user_secret[0].secret_arn
  rotation_enabled = false
}
