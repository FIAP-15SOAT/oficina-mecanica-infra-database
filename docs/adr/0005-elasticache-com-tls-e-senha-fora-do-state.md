# ADR 0005: ElastiCache for Valkey com TLS e senha fora do state

## Status

Aceito — 2026-10-23

## Contexto

Na arquitetura de microsserviços da Fase 4, cada serviço utiliza um banco NoSQL chave-valor para cache do próprio domínio (padrão cache-aside com TTL de 12 h e, no `identity-service`, códigos temporários de redefinição de senha com TTL de 10 min e incremento atômico).

Assim como a master password do RDS nunca transita pelo state do Terraform ([ADR 0003](0003-master-password-gerenciada-pelo-rds.md)), a credencial do cache (`auth_token`) não deve aparecer no `terraform.tfstate`, na saída do `terraform plan`, em variáveis do Terraform, em outputs nem em secrets estáticos do GitHub Actions. Além disso, o Amazon ElastiCache exige criptografia em trânsito (`transit_encryption_enabled = true`) para habilitar autenticação por `auth_token`.

## Decisão

Provisionar em `terraform/elasticache.tf` um replication group **Amazon ElastiCache for Valkey 9.1** por serviço, com TLS obrigatório e senha gerada e aplicada exclusivamente por recursos efêmeros e argumentos write-only do Terraform (`>= 1.11.0`, provider `hashicorp/aws >= 6.62.0, < 7.0.0`):

1. **Replication group gerenciado (`aws_elasticache_replication_group.valkey`)**:
   - `replication_group_id = "cache-${var.project_name}-${var.service_context}"` (neste repositório, `cache-oficina-mecanica-work-order`).
   - `engine = "valkey"`, `engine_version = "9.1"`, `node_type = "cache.t4g.micro"`, `num_cache_clusters = 1`, `automatic_failover_enabled = false`, `port = 6379`.
   - `subnet_group_name` nas subnets privadas da VPC (`cachesng-oficina-mecanica-work-order`) e `security_group_ids = [aws_security_group.secgrp_cache.id]` (entrada TCP `6379` apenas a partir de `eks_nodes_security_group_id`).
   - `transit_encryption_enabled = true`, `transit_encryption_mode = "required"` e `at_rest_encryption_enabled = true`.
   - `apply_immediately = true` e `snapshot_retention_limit = 0`.

2. **Senha efêmera e argumentos write-only**:
   - Gerar o token em tempo de execução com `ephemeral "aws_secretsmanager_random_password" "cache_auth_token"` (`password_length = 64`, `exclude_punctuation = true`, para uso direto na URL `rediss://`).
   - Aplicar o token ao replication group via `auth_token_wo` com `auth_token_wo_version = 1`.
   - Criar o secret `cache-oficina-mecanica-work-order-auth-token` (`recovery_window_in_days = 0`, permitindo recriação imediata do mesmo nome em novas sessões do Learner Lab) e gravar o token em `aws_secretsmanager_secret_version` via `secret_string_wo` com `secret_string_wo_version = 1`.

3. **Descoberta pelo CD do serviço**:
   - O CD do serviço consulta o endpoint primário em `DescribeReplicationGroups` pelo identificador fixo `cache-oficina-mecanica-work-order`, lê o token em `GetSecretValue` pelo nome fixo `cache-oficina-mecanica-work-order-auth-token` e materializa `REDIS_URL=rediss://:<token>@<endpoint>:6379` no Secret Kubernetes `cache-credentials`, sem ler o state do Terraform.

## Alternativas consideradas

- **ElastiCache protegido apenas por Security Group, sem TLS e sem senha**: deixaria o cache sem autenticação em trânsito e em desacordo com o requisito de exigir TLS e credencial em todas as conexões de dados.
- **`random_password` ou variável sensível com `auth_token` e `secret_string` convencionais**: gravaria a senha em texto plano no `terraform.tfstate` no S3, violando a política de zero segredo no state estabelecida no ADR 0003.
- **ElastiCache Serverless**: bloqueado pelas restrições IAM da conta AWS Academy Learner Lab.
- **Valkey auto-hospedado em pod no EKS**: consumiria memória e vagas de pod nos nós `t3.medium` do cluster e deixaria de usar o serviço gerenciado da AWS; mantido apenas como contingência caso o Learner Lab bloqueie a criação real do ElastiCache (ver seção "Revisar se").
- **Amazon DynamoDB**: nos códigos de reset de senha, o TTL do DynamoDB expira com atraso assíncrono (exigindo filtro manual no leitor), enquanto o Valkey oferece expiração exata (`EXPIRE`) e incremento atômico (`HINCRBY`); nos demais serviços, cache sobre DynamoDB não traria ganho de latência frente ao PostgreSQL e adicionaria outra tecnologia ao stack.

## Consequências

- **Positivas**:
  - Nenhuma senha ou token do cache é gravado no `terraform.tfstate`, exibido no `terraform plan` ou armazenado no GitHub Actions.
  - Em planos subsequentes na mesma sessão, como `auth_token_wo_version` e `secret_string_wo_version` permanecem `1`, o Terraform não reenvia nem rotaciona a senha desnecessariamente.
  - `recovery_window_in_days = 0` permite destruir o ambiente ao fim da sessão do Learner Lab e recriar o secret com o mesmo nome na sessão seguinte.
- **Negativas / Trade-offs**:
  - Exige Terraform `>= 1.11.0` e provider AWS `>= 6.62.0`.
  - Para forçar a rotação do token num ambiente já provisionado sem recriar os recursos, é necessário incrementar `auth_token_wo_version` e `secret_string_wo_version`.

## Revisar se

- A criação real do `aws_elasticache_replication_group` for barrada pela política IAM do AWS Academy Learner Lab durante o apply (item de validação **V2** / risco **R2** da arquitetura): registrar o erro da AWS CLI/Terraform e acionar a contingência prevista na §25 da arquitetura — executar `valkey/valkey:9.1` em pod no namespace do serviço no EKS com `--requirepass`, mantendo o mesmo código da aplicação e alterando apenas a URL materializada pelo CD.
