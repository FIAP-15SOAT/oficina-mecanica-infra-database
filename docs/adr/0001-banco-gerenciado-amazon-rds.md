# ADR 0001: Banco de dados relacional como serviço gerenciado (Amazon RDS)

## Status

Aceito — 2026-09-07

## Contexto

A escolha da **tecnologia** de banco de dados (PostgreSQL, e por quê) já está registrada no repositório da aplicação — ver [ADR 0001 do `oficina-mecanica-work-order-service`](https://github.com/FIAP-15SOAT/oficina-mecanica-work-order-service/blob/main/docs/adr/0001-uso-do-postgresql-como-banco-de-dados.md). Esta ADR trata de uma decisão diferente e específica deste repositório: **onde e como esse PostgreSQL roda** — como um serviço gerenciado pela nuvem, ou auto-hospedado (dentro do cluster Kubernetes ou numa instância EC2 dedicada).

O ambiente é `prod-simulated` em conta AWS Academy, com orçamento limitado e infraestrutura descrita na [visão da API](https://github.com/FIAP-15SOAT/oficina-mecanica-work-order-service/blob/main/docs/infra/overview.md). Na fase anterior, PostgreSQL no EKS com armazenamento `emptyDir` não oferecia persistência entre reagendamentos de pods. O banco atual é um recurso RDS independente do cluster.

## Decisão

Provisionar o PostgreSQL como um serviço **totalmente gerenciado pela AWS**: **Amazon RDS**, versão do engine `16.9`, instância `db.t4g.micro`, `20 GiB` de armazenamento GP3 com criptografia em repouso (`storage_encrypted = true`), **fora do cluster Kubernetes**, nas subnets privadas da VPC provisionada por `oficina-mecanica-infra-base`. Acesso restrito à CIDR da VPC via Security Group dedicado (porta `5432`), sem acesso público (`publicly_accessible = false`).

Dado o orçamento de laboratório, a instância é deliberadamente **Single-AZ** (`multi_az = false`), sem backups automatizados (`backup_retention_period = 0`) e sem margem de autoscaling de armazenamento (`db_max_allocated_storage` igual a `db_allocated_storage`, o que desabilita o crescimento automático).

## Alternativas consideradas

### PostgreSQL auto-hospedado dentro do cluster EKS

Foi a abordagem de uma fase anterior do projeto — um `StatefulSet` com volume `emptyDir`. Descartada (e não uma alternativa hipotética, mas uma tentativa real revertida) porque o EBS CSI Driver, necessário para prover volumes persistentes reais (`gp2`/`gp3`) aos pods do EKS, exige credenciais IAM/IRSA que a conta AWS Academy bloqueia — o resultado prático era um banco que perdia todos os dados a cada reagendamento de pod, inviável para qualquer ambiente que precise sobreviver a um restart.

Nas tentativas históricas com `gp2`/`gp3`, o EBS CSI Controller entrou em `CrashLoopBackOff`; os diagnósticos apontaram ausência de credenciais/IRSA e negações IAM para o provisionamento de volumes. Os PVCs permaneciam `Pending`, impedindo a subida dos pods e levando o apply a timeout. `emptyDir` contornava o provisionamento, mas perdia os dados com a remoção do pod; `hostPath` prendia os dados ao nó e não resolvia a persistência entre reagendamentos. Esse registro explica a escolha do RDS e não é uma instrução para restaurar o banco no EKS.

### PostgreSQL auto-hospedado numa instância EC2 dedicada (fora do EKS)

Evitaria a limitação do EBS CSI Driver dentro do cluster, já que um volume EBS anexado diretamente a uma instância EC2 não depende do CSI driver do Kubernetes. Descartada porque:

- Exigiria operar manualmente patching de SO, backups, monitoração de disco e failover — todo o trabalho operacional que um serviço gerenciado (RDS) já resolve.
- Não aproveitaria nenhum dos recursos nativos de RDS (snapshots automatizados, criptografia em repouso integrada, upgrade de versão menor automático) sem reimplementá-los manualmente.

### RDS Multi-AZ

Daria alta disponibilidade real, com failover automático para uma réplica em standby noutra zona de disponibilidade. Descartado nesta entrega por custo: Multi-AZ duplica o custo da instância RDS, consumindo crédito de laboratório que já é escasso e majoritariamente consumido pelo control plane do EKS e pelo NAT Gateway (ver [ADR 0001 de infra-base — restrições do laboratório](https://github.com/FIAP-15SOAT/oficina-mecanica-infra-base/blob/main/docs/adr/0001-escolha-de-nuvem-e-infra-base.md)). Aceito como risco residual: uma indisponibilidade do RDS hoje é uma indisponibilidade de todo o sistema, sem failover automático.

### Aurora PostgreSQL (Serverless ou provisionado)

Ofereceria melhor elasticidade (Aurora Serverless v2 escala capacidade automaticamente) e maior durabilidade (armazenamento distribuído em 3 AZs por padrão). Descartado porque o custo mínimo de Aurora, mesmo em modo Serverless, é superior ao de uma instância RDS `db.t4g.micro` de uso geral — para o volume de dados e tráfego deste laboratório, a diferença de capacidade não se paga no orçamento disponível.

## Consequências

### Positivas

- **Persistência real, resolvendo o problema da fase anterior**: dados sobrevivem a reagendamento de pods, restart de nodes, e até a recriação do cluster EKS — o banco é uma stack Terraform independente, com seu próprio ciclo de vida.
- **Operação delegada à AWS**: patching de versão menor automático (`auto_minor_version_upgrade = true`), criptografia em repouso nativa, sem esforço operacional manual de storage.
- **Isolamento de rede**: acesso restrito à CIDR da VPC via Security Group dedicado, sem exposição pública.
- **States separados do cluster Kubernetes**: recriar o EKS não exclui automaticamente o RDS, mas destruir ou mudar o banco interrompe seus consumidores. A ordem operacional remove Lambda/workloads dependentes antes do banco, e a rede compartilhada por último.

### Negativas / Trade-offs

- **Sem redundância entre AZs**: uma indisponibilidade da AZ onde a instância RDS vive derruba o banco inteiro, sem failover automático — Multi-AZ resolveria isso, mas foi descartado por custo nesta entrega.
- **Sem backups automatizados** (`backup_retention_period = 0`): uma perda de dados por erro operacional ou corrupção não tem um snapshot recente para restaurar — decisão de custo/laboratório, não recomendada para produção real.
- **Sem margem de crescimento automático de armazenamento**: `db_max_allocated_storage` igual a `db_allocated_storage` significa que, se os `20 GiB` se esgotarem, a operação falha em vez de crescer automaticamente — exigiria intervenção manual (aumentar o valor e reaplicar) para resolver.
- **`skip_final_snapshot = true`**: destruir a instância não gera um snapshot final — apropriado para o ciclo de vida de laboratório (criar/destruir com frequência), mas seria uma perda de segurança inaceitável em produção.
- **Exclusão sem proteção e segredo sem janela de recuperação**: `deletion_protection=false` no RDS e `recovery_window_in_days=0` no Secrets Manager exigem preservar dados/credenciais necessários antes do destroy.
- **Versão declarada não é medição live**: `auto_minor_version_upgrade=true` permite upgrades menores gerenciados; 16.9 representa o input atual, sem comprovar a versão efetiva da instância.

### Riscos mitigados

- **Perda de dados por reagendamento de pod (risco da fase anterior)**: eliminado por o banco viver fora do cluster, num serviço gerenciado com armazenamento persistente de verdade.
- **Acesso não autorizado à rede do banco**: mitigado pelo Security Group restringindo a porta `5432` à CIDR da VPC e por `publicly_accessible = false`.

## Referências

- [`oficina-mecanica-work-order-service` › ADR 0001 — Uso do PostgreSQL como banco de dados relacional](https://github.com/FIAP-15SOAT/oficina-mecanica-work-order-service/blob/main/docs/adr/0001-uso-do-postgresql-como-banco-de-dados.md)
- [`oficina-mecanica-work-order-service` — Visão de infraestrutura](https://github.com/FIAP-15SOAT/oficina-mecanica-work-order-service/blob/main/docs/infra/overview.md)
- [`oficina-mecanica-work-order-service` › docs/infra/kubernetes.md — Banco de Dados Relacional (Amazon RDS)](https://github.com/FIAP-15SOAT/oficina-mecanica-work-order-service/blob/main/docs/infra/kubernetes.md#banco-de-dados-relacional-amazon-rds)
- `terraform/rds.tf`, `terraform/variables.tf` — configuração corrente da instância.
