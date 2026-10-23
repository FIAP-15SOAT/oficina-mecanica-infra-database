# 🛠️ Runbook — Dados do Work Order (RDS PostgreSQL & ElastiCache for Valkey)

Procedimentos operacionais para provisionar, verificar conectividade e ausência de segredos no state, diagnosticar falhas conhecidas e destruir os recursos de dados do contexto `work-order` (`oficina-mecanica-infra-database-work-order`).

## Índice

- [1. Subida (Provisionamento)](#1-subida-provisionamento)
- [2. Verificação pós-apply (State sem senha e Conectividade)](#2-verificação-pós-apply-state-sem-senha-e-conectividade)
- [3. Derrubada (Encerramento da sessão)](#3-derrubada-encerramento-da-sessão)
- [4. Falhas conhecidas e contingências](#4-falhas-conhecidas-e-contingências)

---

## 1. Subida (Provisionamento)

Este repositório faz parte da **Camada 2** de infraestrutura e depende apenas do state de [`oficina-mecanica-infra-base`](https://github.com/FIAP-15SOAT/oficina-mecanica-infra-base) (`vpc_id`, `private_subnet_ids` e `eks_nodes_security_group_id`). Ele pode subir em paralelo com `oficina-mecanica-infra-k8s`, `oficina-mecanica-infra-messaging` e os demais repositórios de dados.

### Pelo GitHub Actions

```bash
# Disparar o workflow de CD na branch main
gh workflow run cd.yml -R FIAP-15SOAT/oficina-mecanica-infra-database-work-order --ref main

# Acompanhar a execução mais recente do CD
gh run watch -R FIAP-15SOAT/oficina-mecanica-infra-database-work-order
```

### Pelo terminal local

```bash
# Entrar no diretório Terraform do repositório
cd terraform

# Configurar o bucket de state da sessão atual do Learner Lab
export TF_STATE_BUCKET=<nome-do-bucket-s3>
export TF_VAR_aws_base_state_bucket="$TF_STATE_BUCKET"

# Inicializar o backend remoto na chave do contexto work-order
terraform init -reconfigure -backend-config="bucket=$TF_STATE_BUCKET"

# Planejar e aplicar o RDS PostgreSQL 18 e o ElastiCache for Valkey 9.1
terraform apply
```

---

## 2. Verificação pós-apply (State sem senha e Conectividade)

### 2.1 Conferir que o state não contém senha nem token

Os recursos `aws_elasticache_replication_group.valkey` e `aws_secretsmanager_secret_version.cache_auth_token` utilizam argumentos write-only (`auth_token_wo` e `secret_string_wo`). Para comprovar que o `terraform.tfstate` não armazena o token:

```bash
# Verificar que auth_token_wo e secret_string_wo aparecem nulos no state remoto
terraform state pull | jq '
  [
    .resources[]
    | select(.type == "aws_elasticache_replication_group" or .type == "aws_secretsmanager_secret_version")
    | {
        type: .type,
        name: .name,
        auth_token: .instances[0].attributes.auth_token,
        auth_token_wo: .instances[0].attributes.auth_token_wo,
        auth_token_wo_version: .instances[0].attributes.auth_token_wo_version,
        secret_string: .instances[0].attributes.secret_string,
        secret_string_wo: .instances[0].attributes.secret_string_wo,
        secret_string_wo_version: .instances[0].attributes.secret_string_wo_version
      }
  ]'
```

Resultado esperado: `auth_token`, `auth_token_wo`, `secret_string` e `secret_string_wo` com valor `null`, e apenas `auth_token_wo_version: 1` e `secret_string_wo_version: 1` preenchidos. Um segundo `terraform plan` seguido imediatamente após o apply deve reportar `No changes. Your infrastructure matches the configuration.`

### 2.2 Testar conexão ao RDS (`5432`) e ao ElastiCache (`rediss://` na `6379`) a partir de um pod no EKS

Como os Security Groups `secgrp-rds-oficina-mecanica-work-order` e `secgrp-cache-oficina-mecanica-work-order` aceitam tráfego apenas a partir do Security Group de identidade dos nós do EKS (`secgrp-eks-nodes-oficina-mecanica`, mais a regra provisória das subnets privadas no RDS até a C-20), o teste de conectividade deve partir de um pod no cluster:

```bash
# 1. Obter os endpoints e o token da sessão atual via AWS CLI
RDS_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier rds-oficina-mecanica-work-order \
  --query 'DBInstances[0].Endpoint.Address' --output text)

RDS_SECRET_ARN=$(aws rds describe-db-instances \
  --db-instance-identifier rds-oficina-mecanica-work-order \
  --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text)

RDS_PASS=$(aws secretsmanager get-secret-value \
  --secret-id "$RDS_SECRET_ARN" \
  --query 'SecretString' --output text | jq -r '.password')

CACHE_HOST=$(aws elasticache describe-replication-groups \
  --replication-group-id cache-oficina-mecanica-work-order \
  --query 'ReplicationGroups[0].NodeGroups[0].PrimaryEndpoint.Address' --output text)

CACHE_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id cache-oficina-mecanica-work-order-auth-token \
  --query 'SecretString' --output text)

# 2. Testar PING com TLS + senha no ElastiCache for Valkey a partir de um pod efêmero no namespace work-order (esperado: PONG)
kubectl run valkey-verify --rm -i --restart=Never -n work-order \
  --image=valkey/valkey:9.1 \
  --env="CACHE_HOST=$CACHE_HOST" \
  --env="CACHE_TOKEN=$CACHE_TOKEN" \
  -- sh -c 'valkey-cli --tls -h "$CACHE_HOST" -p 6379 -a "$CACHE_TOKEN" --no-auth-warning PING'

# 3. Confirmar que conexão sem senha no ElastiCache é recusada (esperado: NOAUTH Authentication required)
kubectl run valkey-noauth --rm -i --restart=Never -n work-order \
  --image=valkey/valkey:9.1 \
  --env="CACHE_HOST=$CACHE_HOST" \
  -- sh -c 'valkey-cli --tls -h "$CACHE_HOST" -p 6379 PING'

# 4. Testar consulta SQL no RDS PostgreSQL 18 a partir de um pod efêmero no namespace work-order
kubectl run pg-verify --rm -i --restart=Never -n work-order \
  --image=postgres:18-alpine \
  --env="PGPASSWORD=$RDS_PASS" \
  --env="RDS_HOST=$RDS_HOST" \
  -- psql -h "$RDS_HOST" -U techchallenge -d techchallenge -c "SELECT version();"
```

---

## 3. Derrubada (Encerramento da sessão)

Destrua os recursos deste repositório **depois** de encerrar ou remover as Lambdas e workloads dependentes e **antes** de destruir `oficina-mecanica-infra-base` (caso contrário, a remoção das subnets privadas e do `secgrp-eks-nodes-oficina-mecanica` na `infra-base` falhará por `DependencyViolation`):

```bash
# Entrar no diretório Terraform e inicializar o backend remoto
cd terraform
export TF_STATE_BUCKET=<nome-do-bucket-s3>
export TF_VAR_aws_base_state_bucket="$TF_STATE_BUCKET"
terraform init -reconfigure -backend-config="bucket=$TF_STATE_BUCKET"

# Destruir o RDS, o ElastiCache, os Security Groups, os subnet groups e o secret
terraform destroy -auto-approve
```

---

## 4. Falhas conhecidas e contingências

### 4.1 Criação do ElastiCache bloqueada no AWS Academy Learner Lab (Item V2 / Risco R2)

- **Sintoma:** `terraform apply` falha em `aws_elasticache_replication_group.valkey` com erro `AccessDenied` ou restrição de política IAM da conta `voclabs`.
- **Diagnóstico e Contingência (§25 da arquitetura):**
  1. Registrar a mensagem de erro exata na change correspondente e anotar a revisão da decisão arquitetural AD-13 / [ADR 0005](adr/0005-elasticache-com-tls-e-senha-fora-do-state.md).
  2. Acionar a contingência prevista na arquitetura: implantar um pod `valkey/valkey:9.1` com `--requirepass` dentro do namespace `work-order` no EKS e apontar a `REDIS_URL` (`redis://:<token>@valkey.work-order.svc.cluster.local:6379`) no Secret `cache-credentials` materializado pelo CD do serviço. O código da aplicação permanece inalterado, pois consome apenas a variável `REDIS_URL`.

### 4.2 Secret agendado para exclusão (`InvalidRequestException: You can't create this secret because a secret with this name is already scheduled for deletion`)

- **Causa:** o secret `cache-oficina-mecanica-work-order-auth-token` foi removido anteriormente sem `recovery_window_in_days = 0` ou por fora do Terraform com janela de recuperação padrão (7 a 30 dias).
- **Correção:** forçar a exclusão imediata antes de rodar o `terraform apply`:
  ```bash
  # Excluir imediatamente o secret pendente de deleção na região us-east-1
  aws secretsmanager delete-secret \
    --secret-id cache-oficina-mecanica-work-order-auth-token \
    --force-delete-without-recovery \
    --region us-east-1
  ```

### 4.3 Versão `9.1` do Valkey ou major `18` do PostgreSQL indisponível na região

- **Sintoma:** `InvalidParameterValue` ou ` InvalidParameterCombination` ao criar o replication group ou a instância RDS.
- **Diagnóstico:**
  ```bash
  # Listar versões disponíveis do engine valkey no ElastiCache em us-east-1
  aws elasticache describe-cache-engine-versions --engine valkey --region us-east-1 \
    --query 'CacheEngineVersions[].EngineVersion' --output text

  # Listar versões disponíveis da major 18 do PostgreSQL no RDS em us-east-1
  aws rds describe-db-engine-versions --engine postgres --engine-version 18 --region us-east-1 \
    --query 'DBEngineVersions[].EngineVersion' --output text
  ```
- **Correção:** se a `9.1` do Valkey estiver temporariamente indisponível na região, utilizar a versão compatível `9.0` e registrar o ajuste na change.

### 4.4 `This object does not have an attribute named eks_nodes_security_group_id`

- **Causa:** o state de `oficina-mecanica-infra-base` no S3 ainda foi gerado antes da change C-02, que exporta o Security Group de identidade dos nós do EKS (`eks_nodes_security_group_id`).
- **Correção:** executar o CD (ou `terraform apply`) de `oficina-mecanica-infra-base` na `main` antes de rodar o `plan`/`apply` deste repositório.

Voltar ao [README](../README.md).
