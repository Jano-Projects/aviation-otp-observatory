# Fase 1: passo a passo (Debian 13)

No fim deste guia vai ter:

- um Oracle Database 23ai a correr no seu computador, dentro do Docker;
- o esquema `OTP` com tabelas, packages PL/SQL e testes utPLSQL;
- meses reais de voos da ANAC carregados e prontos a consultar;
- o projeto no seu GitHub, com o CI (testes automáticos) a verde.

Tempo estimado: cerca de 1 hora na primeira vez, a maior parte à espera de downloads.

> Todos os comandos são para o **terminal do Debian 13 (Trixie)**. Os que começam por `sudo`
> pedem a sua palavra-passe de utilizador.

---

## Passo 1: instalar o Docker Engine

No Linux não precisa do Docker Desktop: o Docker corre diretamente no sistema, sem WSL2 e
sem máquina virtual. Use o repositório oficial do Docker, porque o pacote `docker.io` do
Debian não traz o plugin `docker compose` mais recente.

```bash
# 1. Chave e repositório oficiais do Docker
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

# 2. Instalar o Docker e o plugin Compose
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 3. Permitir usar o Docker sem sudo
sudo usermod -aG docker $USER
```

**Termine a sessão e volte a entrar** (ou reinicie o computador), para o seu utilizador
passar a pertencer ao grupo `docker`.

O Docker arranca sozinho quando o computador liga. Não há nada para abrir.

## Passo 2: instalar Git, Python e VS Code

```bash
sudo apt install -y git python3 python3-venv python3-pip unzip
```

O Debian 13 já traz o Python 3.13. O `python3-venv` é necessário porque o Debian não deixa
instalar bibliotecas com `pip` no Python do sistema. Por isso, o projeto usa um ambiente
virtual (`.venv`) só dele.

**VS Code:** descarregue o pacote `.deb` em https://code.visualstudio.com/ e instale-o:

```bash
sudo apt install -y ~/Transferências/code_*.deb    # ou ~/Downloads, conforme o idioma do sistema
```

Dentro do VS Code, em Extensões, instale **Oracle SQL Developer Extension for VSCode**.

### Confirmar que está tudo pronto

```bash
docker --version
docker compose version
docker run --rm hello-world
git --version
python3 --version
free -h
```

- O `hello-world` deve dizer *Hello from Docker!* **sem usar sudo**. Se der
  `permission denied`, ainda não terminou a sessão depois do passo 1.
- Em `free -h`, a coluna *available* deve mostrar pelo menos **4 GB** livres para o Oracle.

## Passo 3: pôr o projeto no seu GitHub

1. Descompacte o projeto, por exemplo em `~/projetos`:

   ```bash
   mkdir -p ~/projetos
   unzip ~/Transferências/aviation-otp-observatory.zip -d ~/projetos
   cd ~/projetos/aviation-otp-observatory
   ```

2. No GitHub, clique em **New repository**:
   - Nome: `aviation-otp-observatory`
   - **Public**
   - **Não** marque "Add a README" (o projeto já tem um).
3. Troque `USERNAME` no README pelo seu utilizador do GitHub (substitua `SEU-UTILIZADOR`):

   ```bash
   sed -i 's/USERNAME/SEU-UTILIZADOR/g' README.md
   ```

4. Primeiro commit e push:

   ```bash
   git init -b main
   git config user.name  "Victor Correa"
   git config user.email "o-seu-email-do-github@exemplo.com"
   git add .
   git commit -m "feat: phase 1 - Oracle 23ai schema, PL/SQL load package and utPLSQL tests"
   git remote add origin https://github.com/SEU-UTILIZADOR/aviation-otp-observatory.git
   git push -u origin main
   ```

Use o e-mail **pessoal** da sua conta do GitHub, para os commits aparecerem no seu perfil.

> **Autenticação no push:** o GitHub já não aceita a palavra-passe da conta no terminal.
> A forma mais simples é instalar o GitHub CLI (`sudo apt install -y gh`), correr
> `gh auth login` uma vez (escolha GitHub.com → HTTPS → login pelo browser) e repetir o
> `git push -u origin main`.

Logo após o push, o GitHub começa a correr os testes sozinho (separador **Actions**).
Pode continuar com os passos seguintes enquanto ele trabalha.

## Passo 4: criar o ambiente Python do projeto

```bash
cd ~/projetos/aviation-otp-observatory
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

O prompt passa a começar por `(.venv)`. Isso indica que o ambiente está ativo.

> **Em cada terminal novo**, antes de usar o projeto, entre na pasta e corra
> `source .venv/bin/activate`. Com o ambiente ativo, o comando `python` aponta para o Python
> do projeto, e é esse que os passos seguintes usam.

## Passo 5: ligar a base de dados

```bash
python tasks.py up
```

O que acontece:
- é criado o ficheiro `.env` com as palavras-passe locais (pode editá-las antes, se quiser);
- o Docker descarrega a imagem do Oracle (alguns GB, **só na primeira vez**);
- a base é criada e o comando espera até ela estar pronta.

Na primeira vez demora 5 a 15 minutos, conforme a internet. Nas seguintes, cerca de 30 segundos.
Termina com `==> Database is ready`.

## Passo 6: instalar o esquema e o utPLSQL

```bash
python tasks.py install
```

Isto faz três coisas:
1. cria o utilizador `OTP` (o "dono" das tabelas do projeto);
2. descarrega e instala o **utPLSQL**, a framework de testes para PL/SQL (cerca de 1 minuto);
3. corre o `db/install.sql`: tabelas, view e packages, e confirma que nada ficou inválido.

Pode correr este comando as vezes que quiser: ele só cria o que ainda não existe e atualiza
o código PL/SQL.

## Passo 7: correr os testes

```bash
python tasks.py test
```

Deve ver duas suites e, no fim:

```
18 tests, 0 failed, 0 errored, 0 disabled, 0 warning(s)
```

Se algum teste falhar, o comando termina com erro e mostra qual falhou e porquê.

## Passo 8: carregar dados reais

```bash
python tasks.py load --from 2026-01 --to 2026-07
```

Para cada mês, o script:
1. descarrega o ficheiro da ANAC para `data/raw/` (se ainda não o tiver);
2. copia-o tal e qual para a tabela `STG_VRA`;
3. chama `pkg_vra_load.process_file`, que valida, remove duplicados e grava em `CORE_FLIGHT`;
4. faz commit e mostra um resumo:

```
VRA_20267.csv  month=2026-07  status=SUCCESS  staged=89,517  loaded=89,506  rejected=0  duplicates=11 ...
```

Se um mês ainda não estiver publicado, o comando avisa. Use `--keep-going` para saltar os meses
em falta. Também pode descarregar um ficheiro à mão no site da ANAC e carregá-lo com:

```bash
python tasks.py load --file ~/Transferências/VRA_20268.csv
```

## Passo 9: ver o resultado

```bash
python tasks.py status
```

Mostra os últimos carregamentos e, por mês, o número de voos, de cancelamentos e a
percentagem de pontualidade.

Para explorar com SQL no **VS Code** (extensão Oracle SQL Developer), crie uma ligação com:

| Campo | Valor |
|---|---|
| Username | `otp` |
| Password | a de `OTP_PASSWORD` no `.env` (por defeito `Otp_App_2026`) |
| Hostname | `localhost` |
| Port | `1521` |
| Service name | `FREEPDB1` |

Algumas consultas para começar:

```sql
-- Pontualidade por aeroporto de origem (voos domésticos, julho de 2026)
select orig_icao,
       count(*)                          as voos,
       round(100 * avg(on_time_15), 1)   as pontualidade_pct,
       round(avg(arr_delay_min), 1)      as atraso_medio_min
  from core_flight
 where ref_month = date '2026-07-01'
   and line_type = 'N'
 group by orig_icao
having count(*) >= 2000
 order by pontualidade_pct desc;

-- As 10 rotas com mais cancelamentos
select orig_icao || ' -> ' || dest_icao as rota,
       sum(is_cancelled)                as cancelados,
       count(*)                         as voos
  from core_flight
 group by orig_icao, dest_icao
 order by cancelados desc
 fetch first 10 rows only;

-- Histórico de carregamentos
select * from core_load_run order by run_id desc;
```

Também pode abrir o SQL*Plus diretamente: `python tasks.py sql`.

## Passo 10: confirmar o CI no GitHub

No seu repositório, abra o separador **Actions**. O workflow **CI** tem dois trabalhos:

- **Python unit tests**: testa a leitura dos ficheiros (segundos);
- **Oracle 23ai + utPLSQL**: sobe um Oracle real, instala tudo, corre os testes e carrega uma
  amostra real (cerca de 5 a 10 minutos).

Quando ficar verde, o selo **CI passing** aparece no topo do README. É a prova, para quem
visita o projeto, de que o código compila e os testes passam.

---

## O dia a dia

| Situação | Comando |
|---|---|
| Abri um terminal novo | `cd ~/projetos/aviation-otp-observatory && source .venv/bin/activate` |
| Liguei o computador e quero trabalhar | `python tasks.py up` (o Docker já arrancou sozinho) |
| Mudei código PL/SQL | `python tasks.py install` e `python tasks.py test` |
| Guardar no GitHub | `git add .` → `git commit -m "..."` → `git push` |
| Trabalhar noutro computador | passos 1, 2, 4, 5, 6 e 8 (com `git clone` em vez do passo 3); depois `git pull` / `git push` |
| Desligar a base | `python tasks.py down` (os dados ficam guardados) |
| Apagar tudo e começar do zero | `python tasks.py reset` |

O Oracle só corre com o computador ligado. Os dados ficam guardados no disco (volume do
Docker) e voltam quando corre `python tasks.py up`.

## Problemas comuns

| Sintoma | Solução |
|---|---|
| `permission denied ... docker.sock` | Falta o grupo `docker`: `sudo usermod -aG docker $USER` e termine a sessão. |
| `Docker is installed but not running` | `sudo systemctl enable --now docker` |
| `error: externally-managed-environment` no `pip` | Esqueceu-se de ativar o ambiente: `source .venv/bin/activate`. |
| `No module named 'oracledb'` | O mesmo: ative o `.venv` (passo 4). |
| `port is already allocated` (porta 1521) | Já há outro Oracle na máquina. No `.env`, mude `ORACLE_PORT=1522` e corra `python tasks.py up`. |
| `up` demora muito na primeira vez | É o download da imagem. Veja o progresso com `docker compose logs -f oracle`. |
| `SP2-0310: unable to open file` | O Oracle, dentro do contentor, não consegue ler os scripts. Corra `chmod -R o+rX db .cache` na pasta do projeto. |
| `ORA-01017: invalid username/password` | Mudou as palavras-passe no `.env` depois de criar a base. Corra `python tasks.py reset` e depois `up` e `install`. |
| O download de um mês falha | O mês pode ainda não estar publicado. Use `--keep-going`, ou descarregue à mão e use `--file`. |
| Erro ao instalar o utPLSQL | Experimente outra versão no `.env` (por exemplo `UTPLSQL_VERSION=v3.2.2`) e volte a correr `install`. |
| O computador fica lento | O Oracle usa 2 a 3 GB de RAM. Quando não estiver a usar, corra `python tasks.py down`. |

## Checklist da Fase 1

- [ ] `python tasks.py test` mostra 0 failed, 0 errored
- [ ] pelo menos 6 meses carregados (`python tasks.py status`)
- [ ] CI verde no GitHub
- [ ] `USERNAME` trocado no README
- [ ] descrição e *topics* no repositório GitHub: `oracle`, `plsql`, `utplsql`, `aviation`, `open-data`, `data-engineering`

**Próximo passo, Fase 2:** modelo em estrela, package `pkg_otp` com os indicadores,
materialized views e o relatório de tuning "antes/depois".
