# ADR 0003: Master password gerenciada pelo Amazon RDS

## Status

Aceito — 2026-09-13

Substitui o [ADR 0002](0002-credencial-via-variavel-terraform-sensivel.md).

## Contexto

O desenho anterior recebia a senha mestra como variável sensível do Terraform,
gravava esse valor na instância e publicava uma cópia em um Secret criado pela
própria stack. Isso mantinha uma credencial de longa duração no GitHub Actions,
nos inputs do Terraform e no State, além de exigir sincronização manual entre
RDS, Secrets Manager e consumidores.

O RDS pode gerar e administrar sua master password. Nesse modo, ele mantém um
Secret no AWS Secrets Manager e expõe somente seus metadados em
`MasterUserSecret`. O formato contém ao menos `username` e `password` e pode
conter campos adicionais administrados pelo serviço.

## Decisão

Configurar `aws_db_instance.rds_postgres` com
`manage_master_user_password = true` e sem o argumento `password`. A chave de
criptografia não é configurada, portanto o Secret usa a chave padrão do AWS
Secrets Manager. O Terraform conhece apenas o ARN computado em
`master_user_secret[0].secret_arn`, publicado no output
`db_credentials_secret_arn`.

Declarar `aws_secretsmanager_secret_rotation` para esse ARN com
`rotation_enabled = false`. Não há Lambda de rotação nem regra periódica. Uma
mudança futura nesse lifecycle exige nova decisão coordenada com os consumidores.

O Secret é criado, pertence e acompanha o lifecycle da instância RDS. A Lambda
de autenticação continua recebendo o ARN pelo remote state e lendo o valor
diretamente. A API descobre ARN, endpoint, porta, nome do banco e usuário pelo
RDS durante seu CD, lê `AWSCURRENT`, monta `DATABASE_URL` e a materializa no
Secret Kubernetes `database-credentials` antes das migrations e do rollout.

## State e dados sensíveis

`sensitive = true` apenas reduz exibição em CLI; não impede persistência no
State. Por isso, a senha deixa de ser input e deixa de ser escrita por recursos
Terraform. O State corrente deve conter somente metadados, inclusive o ARN
computado, e nenhum `password`, `secret_string` ou `secret_binary` com valor.

Esta change não migra nem higieniza States históricos. Se um State antigo tiver
recebido a senha, sua retenção e remoção devem ser tratadas em operação separada,
sem ler ou imprimir o valor durante a auditoria.

## Alternativas consideradas

### Manter a variável Terraform sensível

Rejeitada porque preserva a credencial no GitHub Actions, nos inputs e no State,
além de manter sincronização manual. Era a decisão do ADR 0002.

### Gerar a senha com `random_password`

Rejeitada porque o valor ainda seria produzido e persistido pelo Terraform e
continuaria exigindo publicação e lifecycle próprios do Secret.

### Habilitar rotação automática agora

Rejeitada porque exige Lambda/estratégia de rotação e consumidores preparados
para refresh/retry sem indisponibilidade. A Lambda atual memoiza sua conexão e
os Pods recebem a URL no início; esse comportamento não foi alterado nesta
change.

### Entregar o Secret diretamente aos Pods com ESO ou Secrets Store CSI/ASCP

Rejeitada para não introduzir controller, driver, IAM de workload ou leitura AWS
pelos Pods. O CD continua sendo a ponte explícita para o Kubernetes.

### Conceder acesso de menor privilégio por consumidor

Desejável em uma evolução, mas fora deste escopo. A mudança centraliza a master
password sem criar usuários de banco ou separar permissões.

### Migrar ou sanear o State histórico nesta change

Rejeitada por ser uma operação diferente, potencialmente destrutiva, que exige
inventário e procedimento próprios. A garantia desta decisão vale para o State
produzido pela configuração nova.

## Consequências

**Positivas.** A senha deixa de circular pelo GitHub e Terraform; RDS e Secrets
Manager mantêm uma única origem de verdade; o output cross-repo permanece
estável; e campos adicionais do Secret não quebram os consumidores.

**Negativas.** O CD da API passa a depender da disponibilidade das APIs RDS e
Secrets Manager. O Secret Kubernetes materializa a URL dentro do cluster e deve
ser tratado como dado sensível. Sem rotação automática, uma troca manual ainda
exige nova execução do CD para materializar a URL e renovação explícita dos Pods
existentes. No escopo greenfield, não há annotation de versão; com a mesma imagem,
a atualização isolada do Secret não força um novo rollout.

## Referências

- [AWS — Password management with Amazon RDS and AWS Secrets Manager](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html)
- [Terraform AWS Provider — `aws_db_instance`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance)
- [Terraform AWS Provider — `aws_secretsmanager_secret_rotation`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_rotation)
- [ADR 0001 — Banco gerenciado no Amazon RDS](0001-banco-gerenciado-amazon-rds.md)
