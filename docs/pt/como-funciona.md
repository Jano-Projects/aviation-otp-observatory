# Como funciona o projeto, ficheiro a ficheiro

Este documento explica **o que faz cada parte do código e porque foi feita assim**.
Serve para perceber o projeto por dentro e para o saber defender numa entrevista técnica.

Leia pela ordem: primeiro a visão geral, depois cada camada, por fim o percurso de um
ficheiro desde a ANAC até à tabela final.

---

## 1. Visão geral

```
aviation-otp-observatory/
├── docker-compose.yml        ← liga o Oracle 23ai num contentor
├── .env.example              ← palavras-passe e porta (modelo)
├── tasks.py                  ← "comando central": up, install, test, load, status...
├── requirements*.txt         ← bibliotecas Python
├── loader/                   ← Python: ler, descarregar e enviar ficheiros para o Oracle
│   ├── vra_file.py
│   ├── download.py
│   └── db.py
├── db/                       ← tudo o que corre DENTRO do Oracle
│   ├── install.sql           ← script mestre de instalação
│   ├── admin/                ← criação do utilizador e verificação de objetos inválidos
│   ├── ddl/                  ← tabelas e índices
│   ├── views/                ← view que transforma texto em dados tipados
│   ├── packages/             ← lógica PL/SQL (regras e carga)
│   └── tests/                ← testes utPLSQL
├── tests/                    ← testes Python e ficheiro de amostra real
├── .github/workflows/ci.yml  ← testes automáticos no GitHub
└── docs/                     ← documentação
```

O princípio que guia tudo: **o Python só transporta, o Oracle decide.**
O Python lê o ficheiro e copia-o tal e qual para a base. Todas as regras (o que é válido,
como se calcula o atraso, o que é duplicado) estão em PL/SQL, num único sítio e testadas.
É o que se espera de um projeto de PL/SQL Developer.

As três camadas de dados:

| Camada | Tabela(s) | O que guarda |
|---|---|---|
| **Staging** (receção) | `STG_VRA` | o ficheiro da ANAC tal e qual, tudo como texto |
| **Transformação** | `STG_VRA_V` (view) | os mesmos dados, tipados e com o veredicto de validação |
| **Core** (dados limpos) | `CORE_FLIGHT`, `CORE_AIRLINE`, `CORE_AIRPORT`, `CORE_VRA_REJECT`, `CORE_LOAD_RUN` | dados validados, sem duplicados, mais auditoria |

---

## 2. Infraestrutura

### `docker-compose.yml`

Descreve o contentor do Oracle. As partes importantes:

```yaml
image: gvenzl/oracle-free:23
```
Imagem pública com o **Oracle Database 23ai Free**, a versão gratuita oficial da Oracle.
É a imagem mais usada para desenvolvimento e CI.

```yaml
ports:
  - "${ORACLE_PORT:-1521}:1521"
```
Expõe a porta 1521 do contentor na porta 1521 da máquina. O `${ORACLE_PORT:-1521}` lê o valor
do `.env` e usa 1521 se não houver nenhum.

```yaml
volumes:
  - oradata:/opt/oracle/oradata          # ficheiros da base: sobrevivem a reinícios
  - ./db:/workspace/db:ro                 # os nossos scripts SQL, só de leitura
  - ./.cache/utplsql:/workspace/utplsql:ro
```
- **`oradata`** é um *volume* do Docker. É por causa dele que os dados não se perdem quando
  desliga o computador.
- **`./db`** aparece dentro do contentor em `/workspace/db`. Assim, o SQL*Plus que está dentro
  do contentor consegue correr os nossos scripts sem copiar nada.

```yaml
healthcheck:
  test: ["CMD", "healthcheck.sh"]
```
O Docker pergunta de 10 em 10 segundos se a base já aceita ligações. O `tasks.py up` espera
até o estado ser `healthy`.

### `.env.example` e `.env`

Palavras-passe e configuração local. O `tasks.py` copia o `.env.example` para `.env` na
primeira utilização. O `.env` está no `.gitignore`, por isso nunca vai para o GitHub.

### `.gitignore` e `.gitattributes`

- `.gitignore`: o que **não** vai para o GitHub (`.env`, dados descarregados `data/`,
  utPLSQL descarregado `.cache/`, ficheiros temporários do Python).
- `.gitattributes`: força quebras de linha Linux (LF) nos scripts, porque o SQL*Plus corre
  em Linux dentro do contentor. O ficheiro de amostra da ANAC é mantido **byte a byte**, com
  BOM e CRLF, para os testes usarem o formato real.

---

## 3. `tasks.py`: o comando central

Em vez de decorar comandos do Docker e do SQL*Plus, tudo passa por `python tasks.py <comando>`.
Funciona igual em Linux, Mac e Windows.

| Comando | O que faz por dentro |
|---|---|
| `up` | cria o `.env` se faltar → `docker compose up -d` → espera pelo estado `healthy` |
| `install` | cria o utilizador OTP (como SYS) → descarrega e instala o utPLSQL → corre `db/install.sql` (como OTP) |
| `test` | compila os packages de teste → corre todos os testes utPLSQL → falha se algum falhar |
| `load` | descarrega meses da ANAC (ou usa `--file`) → envia para `STG_VRA` → chama `pkg_vra_load.process_file` → commit |
| `status` | mostra os últimos carregamentos e os voos por mês |
| `sql` | abre o SQL*Plus interativo como OTP |
| `down` / `reset` | para o contentor / apaga também os dados |

As funções auxiliares mais importantes:

```python
def sqlplus(logon, script, capture=False, workdir="/tmp"):
    cmd = ["docker", "compose", "exec", "-T", "-w", workdir, SERVICE,
           "sqlplus", "-s", "-L", logon]
    return run(cmd, input=script, ...)
```
Corre o **SQL*Plus dentro do contentor** e envia-lhe o script pelo *stdin*. Assim não precisa
de instalar nenhum cliente Oracle na sua máquina.
- `-s` (*silent*): não mostra o banner do SQL*Plus.
- `-L`: se o login falhar, termina logo, em vez de ficar à espera de outra palavra-passe.
- `-w workdir`: a pasta onde o SQL*Plus arranca. Os scripts usam caminhos relativos
  (`@ddl/010_staging.sql`), por isso arrancam sempre em `/workspace/db`. Foi esta a correção
  feita depois do primeiro CI vermelho.

```python
def utplsql_state(cfg) -> str:   # 'ok', 'broken' ou 'absent'
```
Verifica se o utPLSQL já está instalado **e válido** (o package `UT3.UT` existe e compila).
Se uma instalação anterior ficou a meio (`broken`), o `install` apaga o utilizador `UT3` e
reinstala de raiz. Isto torna o comando **idempotente**: pode corrê-lo as vezes que quiser.

---

## 4. Python: `loader/`

### `loader/vra_file.py`: ler o ficheiro da ANAC

Não toca na base nem na internet, por isso é fácil de testar com `pytest`.

**O formato real (medido, não adivinhado):**
- linha 1: `Atualizado em: 2026-08-28` (não é o cabeçalho!);
- linha 2: cabeçalho, com campos entre aspas e separados por `;`;
- UTF-8 com BOM, quebras de linha Windows (CRLF).

**Mapeamento de colunas por "aliases":**

```python
COLUMN_ALIASES = {
    "airline_icao": ("icaoempresaaerea", "siglaicaoempresaaerea"),
    "flight_no":    ("numerovoo",),
    ...
}
```
Os nomes das colunas são normalizados: minúsculas, sem acentos, só letras e números. Por
exemplo, `"Código Autorização (DI)"` passa a `"codigoautorizacaodi"`. Assim, o mesmo código lê
o formato atual (`ICAO Empresa Aérea`) e o antigo (`Sigla ICAO Empresa Aérea`), e não depende
da ordem das colunas.

**`open_vra()`** procura o cabeçalho nas primeiras 5 linhas: a primeira linha cujas colunas
batem com os aliases obrigatórios.

**`iter_staging_rows()`** devolve, linha a linha, um tuplo pronto para `INSERT`:
`(nome_do_ficheiro, número_da_linha, empresa, voo, ..., justificativa)`.
Os valores ficam **como texto**: `"null"` continua `"null"` e
`"2026-07-19 15:15:00.100000000"` continua assim. Quem os interpreta é o Oracle.

**`ref_month_from_name()`**: `VRA_20267.csv` → 1 de julho de 2026. É a mesma regra que existe
em PL/SQL (`pkg_vra_util.ref_month_from_file`), e as duas são testadas.

### `loader/download.py`: descarregar da ANAC

- Monta o endereço do mês: `.../Voo Regular Ativo (VRA)/2026/07 - Julho/VRA_20267.csv`,
  com o mês por extenso em português e os espaços e o `ç` codificados para URL.
- Tenta três convenções de nome (`VRA_20267`, `VRA_202607`, `VRA_2026_07`). Se nenhuma
  existir, lê a listagem da pasta no servidor e procura qualquer `.csv` com "VRA".
- Repete o pedido até 3 vezes em falhas de rede. Um 404 (mês não publicado) não é repetido.
- Grava primeiro como `.part` e só depois muda o nome. Se a internet cair a meio, não fica um
  ficheiro corrompido com o nome certo.
- Se o ficheiro já existir em `data/raw/`, não o descarrega outra vez (a não ser com `--force`).

### `loader/db.py`: enviar para o Oracle

```python
cur.execute("delete from stg_vra where src_file = :1", [vra.name])
...
cur.executemany(_INSERT, batch)          # lotes de 10 000 linhas
...
run_id = cur.callfunc("pkg_vra_load.process_file", int, [vra.name, ref_month])
conn.commit()
```
1. Apaga do staging uma cópia anterior do mesmo ficheiro (recarregar não duplica).
2. Insere em **lotes** com `executemany`: uma ida à base por cada 10 000 linhas, em vez de
   90 000 idas.
3. Chama a função PL/SQL que faz o trabalho a sério.
4. Faz **um único commit** no fim. Ou fica o mês todo, ou não fica nada.

Usa o `python-oracledb` em modo *thin*: liga-se ao Oracle sem precisar do Oracle Client.

---

## 5. Base de dados: `db/`

### `db/admin/create_app_user.sql`

Corre como **SYS**, o administrador da base. Cria o utilizador `OTP`, dono de todos os objetos
do projeto, só se ainda não existir. Depois dá-lhe apenas os privilégios necessários
(`create table`, `create view`, `create procedure`...): é o **princípio do menor privilégio**.
A aplicação nunca corre como SYS.

### `db/install.sql`: o script mestre

```sql
whenever sqlerror exit failure rollback
@ddl/010_staging.sql
@ddl/020_core.sql
@packages/pkg_vra_util.pks      -- specs primeiro
@packages/pkg_vra_load.pks
@views/stg_vra_v.sql            -- a view precisa da spec do pkg_vra_util
@packages/pkg_vra_util.pkb      -- bodies no fim
@packages/pkg_vra_load.pkb      -- este precisa da view
@admin/check_invalid.sql
```
- `whenever sqlerror exit failure`: ao primeiro erro de SQL, o SQL*Plus para e devolve um
  código de erro (o CI fica vermelho).
- **A ordem importa**, por causa das dependências: specs → view → bodies.
- **`check_invalid.sql`**: o SQL*Plus trata um erro de compilação PL/SQL como *aviso*, não
  como erro, e continuaria em frente. Este script mostra os erros (`user_errors`) e falha de
  propósito se houver algum objeto inválido (`user_objects.status <> 'VALID'`).

### `db/ddl/010_staging.sql`: tabela `STG_VRA`

Uma linha por linha do ficheiro, **todas as colunas `VARCHAR2`**. Porquê texto?
- Converter ao ler esconderia erros de formato: uma data inválida simplesmente "desaparecia".
- Zeros à esquerda em números de voo (`0904`) perdiam-se se a coluna fosse numérica.
- Fica uma cópia fiel do que a ANAC publicou (**linhagem**): sabe-se sempre de onde veio cada
  dado (`src_file` + `line_no`).

A chave primária `(src_file, line_no)` impede carregar a mesma linha duas vezes.

### `db/ddl/020_core.sql`: as tabelas finais

Usa `create table if not exists`, uma novidade do **Oracle 23ai**. O script pode correr
várias vezes sem erro.

**`CORE_LOAD_RUN`**: auditoria. Uma linha por execução da carga, com estado
(`RUNNING`/`SUCCESS`/`FAILED`), horas e contagens (lidas, carregadas, rejeitadas, duplicadas).
A chave é uma **identity column** (`generated always as identity`), a forma moderna de
substituir sequences e triggers.

**`CORE_VRA_REJECT`**: cada linha inválida, com o motivo (`INVALID_ORIGIN`, ...) e o texto
original. **Nada desaparece sem explicação.**

**`CORE_AIRLINE` / `CORE_AIRPORT`**: dimensões. Guardam também o primeiro e o último mês em
que cada código apareceu. Nomes e países são acrescentados na Fase 2.

**`CORE_FLIGHT`**: a tabela principal. Três pontos a saber explicar:

1. **Colunas virtuais**: valores calculados que não ocupam espaço em disco.
   ```sql
   arr_delay_min number generated always as (round((arr_actual - arr_sched) * 1440)) virtual,
   on_time_15    number(1) generated always as (
                   case when status = 'REALIZADO' and arr_sched is not null and arr_actual is not null
                        then case when round((arr_actual - arr_sched) * 1440) <= 15 then 1 else 0 end
                   end) virtual,
   ```
   Subtrair duas datas em Oracle dá **dias**; × 1440 dá **minutos**. O `round` evita erros de
   arredondamento (14,9999 minutos). A regra "pontual = até 15 min" fica escrita **uma única
   vez**, na tabela, em vez de repetida em cada consulta.
   `ON_TIME_15` fica `NULL` (e não 0) para voos onde a pontualidade não se pode medir:
   cancelados ou sem horário previsto. Assim, `avg(on_time_15)` dá diretamente a percentagem
   certa, porque o `avg` ignora os `NULL`.

2. **Particionamento por intervalo**:
   ```sql
   partition by range (ref_month) interval (numtoyminterval(1, 'MONTH'))
   ```
   Cada mês fica numa partição (um "pedaço" físico separado), criada **automaticamente** quando
   chega o primeiro voo desse mês. Uma consulta com `where ref_month = date '2026-07-01'` lê só
   essa partição (*partition pruning*). Recarregar um mês mexe só nesse pedaço.

3. **Índices locais** (`... local`): um índice por partição, alinhado com os dados. Também
   cobrem as chaves estrangeiras, para os `DELETE` e os `JOIN` não fazerem leituras completas.

As **constraints** protegem os dados mesmo que alguém insira à mão: `status` só aceita
`REALIZADO`/`CANCELADO`, `ref_month` tem de ser o dia 1 do mês, e as chaves estrangeiras
garantem que a companhia e os aeroportos existem.

### `db/packages/pkg_vra_util`: as regras (funções puras)

"Puras" quer dizer que não leem nem escrevem tabelas: recebem valores e devolvem um
resultado. Por isso estão marcadas `deterministic` e são fáceis de testar.

**`to_ts(p_value)`**: texto → `DATE`.
```sql
if matches(l_value, '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}') then
  return to_date(substr(l_value, 1, 16), 'YYYY-MM-DD HH24:MI');
elsif matches(l_value, '^\d{2}/\d{2}/\d{4} \d{2}:\d{2}') then
  return to_date(substr(l_value, 1, 16), 'DD/MM/YYYY HH24:MI');
```
- Aceita o formato atual e o antigo.
- `substr(…, 1, 16)` corta os segundos e o `.100000000`, porque a ANAC só tem precisão ao minuto.
- `'null'`, `'N/A'` e vazio devolvem `NULL`.
- **Tratamento de exceções preciso:**
  ```sql
  exception
    when others then
      if sqlcode between -1899 and -1800 then return null; end if;
      raise;
  ```
  Uma data com o formato certo mas impossível (30 de fevereiro, hora 25) gera um erro
  ORA-018xx: é tratada como "não interpretável". **Qualquer outro erro é relançado.** Um
  `when others then return null` simples esconderia problemas reais, e é um erro clássico
  que os revisores de código procuram.

**`ref_month_from_file(p_file_name)`**: extrai o mês do nome do ficheiro com uma expressão
regular (`VRA_(\d{4})_?(\d{1,2})`).

**`reject_reason(...)`**: a regra de validação de uma linha. Devolve `NULL` se a linha é
válida, ou o **primeiro** problema encontrado, por ordem:
1. identificação: companhia com 3 caracteres, número de voo, aeródromos com 4, estado conhecido;
2. horários: se existem, têm de ser interpretáveis;
3. coerência: tem de haver alguma hora de partida, e um voo `REALIZADO` tem de ter horas reais.

### `db/views/stg_vra_v.sql`: onde o texto vira dados

```sql
select s.src_file, s.line_no,
       upper(trim(s.airline_icao))      as airline_icao,
       pkg_vra_util.to_ts(s.dep_sched)  as dep_sched,
       ...
       pkg_vra_util.reject_reason(...)  as reject_reason,
       ... || ';' || ...                as raw_line
  from stg_vra s;
```
É o **único sítio** onde a conversão acontece. O package de carga lê só desta view: se a regra
mudar, muda num lugar. Chamar funções de package dentro de SQL é normal em Oracle; o custo de
desempenho desta abordagem vai ser medido e otimizado na Fase 2 (relatório "antes/depois").

### `db/packages/pkg_vra_load`: a carga

A única função pública:

```sql
function process_file(p_src_file in varchar2, p_ref_month in date default null) return number;
```

O que faz, passo a passo:

```sql
l_run_id := start_run(p_src_file, l_ref_month);   -- 1. regista o início (transação autónoma)
savepoint sp_process_file;                        -- 2. ponto de retorno
select count(*) into l_staged ...;                -- 3. há linhas? se não, erro -20002
l_rejected := reject_invalid_lines(...);          -- 4. inválidas → CORE_VRA_REJECT
register_airlines(...);                           -- 5. MERGE nas companhias
register_airports(...);                           -- 6. MERGE nos aeroportos
l_loaded := replace_month(...);                   -- 7. DELETE do mês + INSERT DISTINCT
mark_success(...);                                -- 8. regista as contagens
return l_run_id;
```

Conceitos importantes:

- **Contrato de transação: a função NÃO faz commit.** Quem chama decide: o Python faz commit
  por ficheiro, e os testes fazem rollback para não deixar lixo. É uma boa prática em packages
  reutilizáveis.

- **`pragma autonomous_transaction`** em `start_run` e `mark_failed`: estas duas rotinas fazem o
  seu próprio commit, independente da transação principal. Se a carga falhar e tudo for
  desfeito, o registo do erro **fica gravado**. Já o `mark_success` é normal (não autónomo),
  de propósito: o "SUCCESS" só fica gravado se os dados também ficarem. Assim, o registo nunca
  diz que algo correu bem quando os dados foram desfeitos.

- **`MERGE`** (*upsert*): numa só instrução, insere o código se é novo, ou atualiza o
  primeiro/último mês se já existe.

- **Idempotência**: `replace_month` apaga o mês e volta a inserir. Carregar o mesmo ficheiro
  duas vezes dá o mesmo resultado, e a ANAC republica ficheiros antigos com correções.

- **`select distinct`** remove as linhas exatamente iguais (a ANAC publica algumas em
  duplicado). Linhas que diferem em qualquer coluna ficam todas.

- **Tratamento de erro:**
  ```sql
  exception
    when others then
      l_error := substr(sqlerrm || chr(10) || dbms_utility.format_error_backtrace, 1, 4000);
      rollback to savepoint sp_process_file;
      mark_failed(l_run_id, l_error);
      raise;
  ```
  Guarda a mensagem **e a linha exata do erro** (`format_error_backtrace`), desfaz só o
  trabalho desta função, regista a falha e relança o erro para quem chamou saber.

- **Exceções com nome** na spec (`e_no_staged_rows` com `-20002`): quem chama pode apanhar o
  erro pelo nome em vez de comparar números.

### `db/tests/`: testes utPLSQL

O **utPLSQL** é a framework de testes de referência para PL/SQL, o equivalente ao JUnit do Java.
Os testes são packages normais com **anotações** em comentários:

```sql
--%suite(pkg_vra_load - from staging to core)
--%rollback(auto)          -- cada teste é desfeito no fim

--%beforeeach              -- corre antes de CADA teste
procedure stage_sample_file;

--%test(Drops exact duplicate lines)
procedure drops_exact_duplicates;

--%test(Fails with ORA-20002 when no lines are staged for the file)
--%throws(-20002)          -- o teste passa SE este erro acontecer
procedure fails_without_staged_lines;
```

E dentro de cada teste, as verificações:
```sql
ut.expect(l_delay).to_equal(-15);
ut.expect(l_on_time).to_be_null();
```

| Suite | O que testa |
|---|---|
| `test_pkg_vra_util` (10 testes) | formatos de data, `null`, datas impossíveis, nomes de ficheiros, cada motivo de rejeição |
| `test_pkg_vra_load` (8 testes) | carga de 6 linhas inventadas (3 válidas, 1 duplicado, 2 inválidas): atrasos, rejeições, duplicados, idempotência, dimensões, auditoria, os dois erros esperados |

Os testes usam o mês **2099-01**, para nunca tocarem em dados reais.

**`run_tests.sql`** corre tudo com `ut.run()`, imprime o resultado e lê a linha de resumo
(`18 tests, 0 failed, 0 errored...`). Depois apaga de `CORE_LOAD_RUN` os registos de auditoria
que os testes criaram (ficheiros do mês falso 2099), porque esses são gravados em transações
autónomas e sobrevivem ao rollback. Se houver falhas, lança um erro, e o SQL*Plus sai com
código ≠ 0 (o CI fica vermelho).

---

## 6. Testes Python: `tests/`

- **`tests/fixtures/VRA_20267_sample.csv`**: 22 linhas **reais** da ANAC (julho de 2026),
  escolhidas para cobrir os casos difíceis: cancelados, voos sem horário previsto, horários com
  `.100000000` e um par de duplicados exatos.
- **`tests/python/test_vra_file.py`**: 15 testes `pytest`: encontrar o cabeçalho, ler a
  amostra, aceitar o formato antigo, recusar um ficheiro que não é VRA, extrair o mês do nome,
  montar os endereços de download.

---

## 7. CI: `.github/workflows/ci.yml`

A cada `git push`, o GitHub cria máquinas Linux temporárias e corre dois trabalhos:

1. **Python unit tests**: instala as dependências e corre o `pytest`. Demora segundos.
2. **Oracle 23ai + utPLSQL** (só se o primeiro passar):
   `tasks.py up` → `install` → `test` → `load --file` (amostra real) → `status`.
   Se algo falhar, mostra os registos do Oracle.

É exatamente o que corre na sua VM. Se funciona no CI, funciona em qualquer máquina com Docker.

---

## 8. O percurso completo de um ficheiro

O que acontece quando corre `python tasks.py load --from 2026-07`:

```
1. download.py   → descarrega VRA_20267.csv para data/raw/
2. vra_file.py   → encontra o cabeçalho na linha 2 e mapeia as 12 colunas
3. db.py         → DELETE no STG_VRA desse ficheiro, depois INSERT de 89 517 linhas (texto)
4. db.py         → chama pkg_vra_load.process_file('VRA_20267.csv', 2026-07-01)
5. PL/SQL        → CORE_LOAD_RUN: nova linha RUNNING (commit autónomo)
6. PL/SQL        → lê STG_VRA_V: cada linha é tipada e validada por pkg_vra_util
7. PL/SQL        → 0 inválidas → CORE_VRA_REJECT
8. PL/SQL        → MERGE em CORE_AIRLINE e CORE_AIRPORT
9. PL/SQL        → DELETE de julho em CORE_FLIGHT, INSERT DISTINCT de 89 506 voos (11 duplicados)
10. PL/SQL       → CORE_LOAD_RUN: SUCCESS com as contagens
11. db.py        → COMMIT (tudo de uma vez)
12. tasks.py     → mostra o resumo
```

---

## 9. Perguntas de entrevista que este projeto lhe permite responder

| Pergunta | Onde está a resposta |
|---|---|
| Como garante que uma carga pode ser repetida sem duplicar dados? | `replace_month` (DELETE + INSERT do mês) e a PK do staging |
| Para que serve uma transação autónoma? Quando **não** a usar? | `start_run` / `mark_failed` vs. `mark_success` |
| Como trata exceções sem esconder erros? | `to_ts` (só ORA-018xx) e `process_file` (regista e relança) |
| Quando usaria particionamento? | `CORE_FLIGHT`: cargas e consultas por mês |
| Índices locais ou globais? | `core_flight_*_ix ... local` |
| Colunas virtuais: vantagens? | `ARR_DELAY_MIN`, `ON_TIME_15`: regra num só sítio, sem espaço em disco |
| Como testa PL/SQL? | utPLSQL, `--%beforeeach`, `--%rollback`, `--%throws`, CI |
| Porque é que o staging é todo texto? | linhagem, erros de formato visíveis, zeros à esquerda |
| Como compilou e validou o código num pipeline? | `install.sql` + `check_invalid.sql` + GitHub Actions |
| O que mudaria para milhões de linhas? | Fase 2: materializar a view numa tabela temporária, `append`/paralelismo, troca de partições |
