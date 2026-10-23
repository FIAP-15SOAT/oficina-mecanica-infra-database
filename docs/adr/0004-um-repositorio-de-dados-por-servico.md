# ADR 0004: Um repositório de dados por serviço

## Status

Aceito — 2026-10-23

## Contexto

Na Fase 3, a solução tinha uma única API (`oficina-mecanica-work-order-service`, então `oficina-mecanica-api`) e um único repositório Terraform de banco (`oficina-mecanica-infra-database`), que provisionava a instância RDS `rds-oficina-mecanica` com state em `infra/prod-simulated/database/terraform.tfstate` e Security Group aberto para toda a CIDR da VPC.

Na Fase 4, a solução foi dividida em quatro microsserviços independentes (`work-order`, `identity`, `billing` e `inventory`), cada um dono exclusivo do próprio banco relacional PostgreSQL e do próprio cache NoSQL (ElastiCache for Valkey), sem banco compartilhado e sem acesso cruzado a credenciais ou conexões de outro contexto. Era necessário definir:

1. como organizar os repositórios e os states Terraform de dados dos quatro serviços;
2. como parametrizar a configuração para que os quatro repositórios mantenham o mesmo desenho sem duplicação ad-hoc;
3. como restringir o acesso de rede no nível de Security Group apenas aos nós do cluster EKS (e, transitoriamente até a C-20, à Lambda `customer-auth` no banco do `work-order`).

## Decisão

1. **Um repositório de dados por serviço (`oficina-mecanica-infra-database-<contexto>`)**:
   - Renomear `oficina-mecanica-infra-database` no GitHub para `oficina-mecanica-infra-database-work-order`, preservando o histórico, os PRs, o ruleset da `main`, o environment `production`, as variables e os secrets.
   - Provisionar neste repositório exclusivamente os recursos de dados do contexto `work-order` — o RDS PostgreSQL 18 (`rds-oficina-mecanica-work-order`), o ElastiCache for Valkey 9.1 (`cache-oficina-mecanica-work-order`), os subnet groups, os Security Groups e os secrets dos dois — com state próprio em `infra/prod-simulated/infra-database-work-order/terraform.tfstate`.
   - Usar este repositório como template para os repositórios `oficina-mecanica-infra-database-identity`, `oficina-mecanica-infra-database-billing` e `oficina-mecanica-infra-database-inventory`.

2. **`service_context` como única variável de contexto**:
   - Declarar `variable "service_context"` em `terraform/variables.tf` (neste repositório, `default = "work-order"`) e derivar em `terraform/locals.tf` todos os nomes e identificadores fixos:
     - `rds-${var.project_name}-${var.service_context}`
     - `dbsng-${var.project_name}-${var.service_context}`
     - `secgrp-rds-${var.project_name}-${var.service_context}`
     - `cache-${var.project_name}-${var.service_context}`
     - `cachesng-${var.project_name}-${var.service_context}`
     - `secgrp-cache-${var.project_name}-${var.service_context}`
     - `cache-${var.project_name}-${var.service_context}-auth-token`
   - Os repositórios dos outros três serviços copiam a mesma estrutura e alteram apenas o default de `service_context` e a chave do backend S3 (além de omitir a regra provisória da Lambda).

3. **Security Groups restritos ao Security Group de identidade dos nós do EKS**:
   - Declarar as regras de entrada inline nos próprios `aws_security_group` deste repositório (`secgrp_rds` na porta `5432` e `secgrp_cache` na porta `6379`) aceitando tráfego exclusivamente a partir de `eks_nodes_security_group_id` (`secgrp-eks-nodes-oficina-mecanica`), lido do remote state do `oficina-mecanica-infra-base`, sem regras de saída (`egress`).
   - Apenas neste repositório (`work-order`), manter um segundo bloco `ingress` provisório na porta `5432` do `secgrp_rds` a partir dos CIDRs das subnets privadas (obtidos via `data "aws_subnet"` sobre `private_subnet_ids` do `infra-base`), para que a Lambda `customer-auth` continue autenticando clientes até que a C-20 migre o fluxo para o `identity-service`.

4. **Outputs escalares estáveis**:
   - Manter os 9 outputs `db_*` (`db_instance_id`, `db_instance_arn`, `db_endpoint`, `db_host`, `db_address`, `db_port`, `db_name`, `db_security_group_id`, `db_credentials_secret_arn`) e adicionar os 4 outputs escalares do cache (`cache_primary_endpoint`, `cache_port`, `cache_auth_token_secret_name`, `cache_security_group_id`), sem expor senha, token ou URL de conexão.

## Alternativas consideradas

- **Um único repositório `oficina-mecanica-infra-database` com `for_each` para os 4 serviços**: concentraria o ciclo de vida, o blast radius e o lock do state de todos os bancos e caches num único pipeline, contrariando a exigência de infraestrutura e persistência isoladas por microsserviço (AD-15, §18.2).
- **Um repositório para todos os RDS e outro para todos os ElastiCache**: separaria por tecnologia em vez de por bounded context, exigindo dois pipelines e dois states para subir ou recriar os dados de um único serviço.
- **Criar um repositório novo para o `work-order` em vez de renomear `oficina-mecanica-infra-database`**: perderia o histórico de commits, os PRs, os checks e a configuração existente de ruleset, environment, secrets e variables no GitHub.
- **Módulo Terraform compartilhado e versionado entre os 4 repositórios de dados**: introduziria sobrecarga de versionamento e publicação de módulo para quatro stacks pequenas de 9 arquivos; manter `service_context` em `variables.tf` e copiar o template com checklist no PR é mais simples e direto.
- **Ler o Security Group do cluster no state do `oficina-mecanica-infra-k8s`**: impediria que os 4 repositórios de dados subissem em paralelo com o `infra-k8s` na camada 2 de provisionamento; usar o `eks_nodes_security_group_id` exportado pelo `infra-base` permite o paralelismo.
- **Regra avulsa (`aws_vpc_security_group_ingress_rule`) no repositório da Lambda ou leitura do SG da Lambda aqui**: declarar a regra fora do repositório dono do SG conflitaria com os blocos `ingress` inline no próximo apply; ler o state da Lambda aqui criaria dependência circular (a Lambda lê o state deste repositório e sobe depois dele).

## Consequências

- **Positivas**:
  - Isolamento completo de state, pipeline e credenciais por bounded context.
  - Os 4 repositórios de dados sobem e são destruídos em paralelo logo após o `infra-base`, sem esperar o cluster EKS.
  - O CD de cada serviço descobre apenas o RDS (`rds-oficina-mecanica-<contexto>`) e o ElastiCache (`cache-oficina-mecanica-<contexto>`) do próprio contexto pelos identificadores fixos.
  - Nenhum recurso na VPC fora dos nós do EKS alcança o cache (e, após a C-20, o RDS).
- **Negativas / Trade-offs**:
  - Mudanças estruturais nos arquivos Terraform precisam ser replicadas nos 4 repositórios de dados, mitigado pelo uso de `service_context` como única variável que muda entre eles.
  - Até a C-20, qualquer ENI nas subnets privadas alcança a porta `5432` do RDS do `work-order` pela regra provisória (ainda assim mais restrita que o CIDR inteiro da VPC e protegida pela senha do RDS).

## Revisar se

- A C-20 (`decommission-customer-auth-lambda`) for concluída: remover o bloco `ingress` provisório das subnets privadas e o `data "aws_subnet" "private"` em `terraform/security_group.tf`.
- O número de repositórios de dados crescer além dos 4 contextos atuais e a manutenção das cópias justificar a extração de um módulo Terraform versionado.
