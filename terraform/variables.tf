variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "oficina-mecanica"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod-simulated"
}

# Remote state inputs from infra-base
variable "aws_base_state_bucket" {
  description = "S3 bucket name containing infra-base remote state"
  type        = string
  default     = "bkt-oficina-mecanica"
}

variable "aws_base_state_key" {
  description = "S3 key for infra-base remote state"
  type        = string
  default     = "infra/prod-simulated/infra-base/terraform.tfstate"
}

variable "aws_base_state_region" {
  description = "AWS region of the infra-base S3 bucket"
  type        = string
  default     = "us-east-1"
}

# RDS Database Configuration
variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.9"
}

variable "db_instance_class" {
  description = "Database instance type (e.g. db.t4g.micro or db.t3.micro)"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage size in GiB"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Maximum storage size in GiB for autoscaling (set equal to allocated_storage to disable)"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "techchallenge"
}

variable "db_username" {
  description = "Master database username"
  type        = string
  default     = "techchallenge"
}

variable "db_port" {
  description = "PostgreSQL database port"
  type        = number
  default     = 5432
}

variable "multi_az" {
  description = "Specifies if the RDS instance is multi-AZ"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Days to retain automated backups (0 to disable)"
  type        = number
  default     = 0
}

variable "skip_final_snapshot" {
  description = "Determines whether a final DB snapshot is created before deleting the instance"
  type        = bool
  default     = true
}
