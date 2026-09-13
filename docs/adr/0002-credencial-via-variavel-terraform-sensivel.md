# ADR 0002: Senha do banco por variável Terraform sensível e publicação no Secrets Manager

## Status

Substituído pelo [ADR 0003](0003-master-password-gerenciada-pelo-rds.md) — 2026-09-13

## Contexto

A instância RDS (ADR 0001) precisa de uma senha mestra do PostgreSQL. Essa senha precisa existir em algum lugar do fluxo de provisionamento — declarada como código, gerenciada por um serviço de segredos, ou gerada automaticamente pela AWS — e cada opção tem implicações diferentes de rotação, auditoria e complexidade operacional.

## Decisão

Receber `db_password`, sem default e com `sensitive=true`, por
`TF_VAR_db_password`. No CI/CD, essa variável de ambiente vem do GitHub Secret
`DB_PASSWORD` ou `TF_VAR_DB_PASSWORD`, nessa ordem. O fallback fictício existe
somente no plan do CI; o CD exige o segredo real. Os nomes GitHub são maiúsculos,
embora a variável de ambiente Terraform termine em `db_password`.

Usar o valor em `aws_db_instance.rds_postgres.password` e publicar uma versão
JSON de `oficina-mecanica/database/credentials`, contendo `username` e
`password`, em `aws_secretsmanager_secret_version.db_credentials`. O output
`db_credentials_secret_arn` é consumido pelo state da Lambda, que lê o segredo
com sua role existente. A API recebe sua configuração de banco e senha pelo
próprio CD, sem leitura automática deste segredo.

Não há senha gerada por `random_password`, `manage_master_user_password` ou
rotação automática. A credencial é definida pelo operador; o Secrets Manager
centraliza sua leitura pela Lambda. O recurso de segredo tem
`recovery_window_in_days=0`, com exclusão imediata no destroy.

## Alternativas consideradas

### Senha mestra gerenciada pelo RDS

`manage_master_user_password` delegaria a gestão da senha ao RDS e usaria seu
segredo gerenciado. Essa opção não está habilitada; o contrato atual recebe a
senha do operador e publica um segredo próprio. A alteração exigiria coordenar
a configuração e os consumidores, sem troca silenciosa nesta revisão.

### Rotação automática no Secrets Manager

Automatizaria a renovação da credencial, mas exige coordenação da alteração no
banco, permissões e atualização dos consumidores. Publicar uma versão de segredo
não habilita rotação. O estado vigente usa troca manual no ciclo de laboratório.

### `random_password` gerado pelo Terraform

Evitaria definir a senha manualmente, mas o valor também seria persistido no
state. A criptografia do backend não impede a leitura por quem tem acesso autorizado ao state. A senha gerada poderia ser publicada em Secrets Manager e consumida pelo ARN do segredo, sem um output de senha; essa alternativa não elimina a persistência da credencial no state nem a necessidade de coordenar os consumidores.

### Senha em `terraform.tfvars` versionado

Seria a opção mais simples operacionalmente — sem necessidade de configurar secrets no GitHub. Descartada de imediato: versionar uma senha de banco de dados em texto plano no repositório é uma prática insegura básica, incompatível com qualquer padrão mínimo de segurança, independentemente do contexto de laboratório.

Descartada para evitar expor uma credencial no Git. O arquivo local é ignorado,
mas esse mecanismo não impede inclusão forçada ou escrita acidental em outro
arquivo. Não fornecer exemplos com senha real nem tratar `sensitive` como
controle que proíbe versionamento.

## Consequências

### Positivas

- **Origem da senha fora do código**: a senha não tem default no código; sua origem operacional é o Secret do pipeline ou a variável de ambiente local.
- A Lambda recebe o ARN estável pelo state e obtém username/password no Secrets Manager, sem carregar a senha como output Terraform.
- **`sensitive = true` reduz exposição acidental**: o Terraform mascara o valor em `plan`/`apply`/logs de CI, evitando que a senha apareça em texto plano na saída de um pipeline.

### Negativas / Trade-offs

- **Sem rotação automática**: a senha permanece a mesma até ser trocada manualmente (atualizando o GitHub Secret e reaplicando) — um processo manual e sujeito a ser esquecido, inadequado para um ambiente de produção real de longa duração.
- **Ainda existe em texto plano no state do Terraform**: `sensitive=true` reduz exposição na saída de plan/apply, mas a senha **fica no state** do RDS e do segredo. Criptografia
do backend não elimina o acesso ao valor por leitores autorizados do state, qualquer pessoa com acesso de leitura ao bucket S3 do state pode extrair a senha atual do arquivo de state, então, a leitura do bucket deve ser restrita.
- **Dependência de disciplina operacional humana**: a segurança do segredo depende inteiramente de quem tem acesso ao GitHub Secret nunca vazá-lo, sem nenhum controle automático adicional (rotação, auditoria de acesso) reforçando isso.
- **A troca é manual**: atualizar a fonte da senha, reaplicar RDS/segredo e alinhar
  consumidores. O Secret Kubernetes da API não se atualiza automaticamente.

### Riscos aceitos

- **Senha estática sem rotação**: aceito para o contexto de laboratório de curta duração; uma conta de produção real exigiria Secrets Manager com rotação automática antes de aceitar este mesmo design.
- **Senha legível no state do Terraform**: aceito porque o bucket S3 do state já tem controle de acesso próprio (fora do escopo desta ADR) e o valor é mascarado nas saídas de CI, reduzindo (não eliminando) a superfície de exposição.

## Referências

- [ADR 0001 — RDS gerenciado](0001-banco-gerenciado-amazon-rds.md)
- [README — Credenciais e pipelines](../../README.md)
