# LojaVirtual

Laboratório cumulativo de Programação de Banco de Dados em T-SQL. O cenário usa dados fictícios e uma instância descartável de SQL Server 2022 Developer. As práticas partem do esquema relacional e chegam a transações concorrentes, planos reais e monitoramento.

## Execução e reprodução

Instale SQL Server 2022 Developer (ou uma versão compatível), Python 3.12 e o cliente Python abaixo. Use uma instância de laboratório na qual o banco `LojaVirtual` ainda não exista. Para repetir em condições equivalentes, inicie outra instância descartável. O executor precisa criar o banco, criar objetos, impersonar o usuário de teste e consultar as DMVs das próprias sessões de laboratório. O usuário de catálogo recebe permissões próprias e é simulado com `EXECUTE AS USER`.

Em Bash, com o servidor disponível:

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install pymssql==2.4.6
export SQL_HOST=127.0.0.1 SQL_PORT=1433 SQL_USER=sa
read -rs -p 'Senha da instância de laboratório: ' SQLCMDPASSWORD
printf '\n'
export SQLCMDPASSWORD
EVIDENCIAS="$PWD/saida-local" python testes/validar.py
unset SQLCMDPASSWORD
```

Use uma conta autorizada na instância isolada e forneça sua senha por variável de ambiente. O executor não exige serviços externos. O código de saída é diferente de zero se uma consulta falhar ou uma asserção divergir. Cada roteiro é aplicado e conferido antes do seguinte e o resumo registra o SHA-256 dos scripts efetivamente utilizados. Os tempos variam conforme a instância e a carga.

No SSMS, conecte-se ao laboratório e abra os oito arquivos na ordem indicada. Rode cada arquivo e confira o log correspondente. Para reproduzir também os testes que exigem sessões paralelas, execute o validador a partir de um banco novo. Em R5, o validador coordena as sessões A e B e consulta o estado de espera em uma terceira conexão. Em R8, uma espera controlada dá tempo à segunda conexão para observar a requisição na DMV. Os arquivos `.sqlplan` abrem no SSMS como planos gráficos e contêm os contadores reais retornados por `SET STATISTICS XML`.

## Roteiros e evidências

| Roteiro | Script | Evidência principal |
|---|---|---|
| 1. Estrutura e CRUD | [01](sql/01-estrutura-crud.sql) | [Conferência, alterações e restrições](evidencias/r01.txt) |
| 2. Consultas e síntese | [02](sql/02-consultas.sql) | [Consultas e respostas gerenciais](evidencias/r02.txt) |
| 3. Objetos programáveis | [03](sql/03-objetos.sql) | [Views, funções e procedures em execução](evidencias/r03.txt) |
| 4. Triggers | [04](sql/04-triggers.sql) | [Auditoria, estoque e rejeição](evidencias/r04.txt) |
| 5. Transações | [05](sql/05-transacoes.sql) | [Commit, rollback, bloqueios e isolamento](evidencias/r05.txt) |
| 6. Cursores | [06](sql/06-cursores.sql) | [Equivalência, liberação e tempos](evidencias/r06.txt) |
| 7. Otimização | [07](sql/07-otimizacao.sql) | [Métricas](evidencias/r07-metricas.json), [plano inicial](evidencias/r07-inicial.sqlplan), [plano após o índice](evidencias/r07-apos-indice.sqlplan) |
| 8. Segurança | [08](sql/08-seguranca.sql) | [Permissões, Query Store e DMV](evidencias/r08.txt) |

[Confira o resumo da execução e os hashes dos scripts.](evidencias/validacao.txt)
