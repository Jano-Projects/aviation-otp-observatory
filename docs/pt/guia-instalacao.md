# Guia de instalação (Debian 13)

Como pôr o projeto a funcionar do zero numa máquina Debian 13, incluindo numa VM VirtualBox.
Tempo estimado: 30 a 60 minutos, a maior parte à espera de downloads.

Cada passo é um **bloco**: copie-o inteiro, cole no terminal e carregue em Enter.
Depois de cada bloco, confirme o **"Deve ver"** antes de passar ao seguinte.

> **Colar no terminal:** use **Ctrl + Shift + V**. No terminal, o Ctrl + V sozinho não funciona.
>
> **Como funciona o código por dentro:** veja [como-funciona.md](como-funciona.md).

| Parte | O que faz | Quando |
|---|---|---|
| A | Preparar a VM | uma vez por máquina |
| B | Instalar as ferramentas | uma vez por máquina |
| C | Obter o projeto | uma vez por máquina |
| D | Pôr o projeto a funcionar | uma vez por máquina |
| E | Usar no dia a dia | sempre |

---

## Parte A: preparar a VM (VirtualBox)

### A1. Recursos da VM

Com a VM **desligada**, no VirtualBox abra **Configurações** e confirme:

| Recurso | Onde | Mínimo |
|---|---|---|
| Memória | Sistema → Placa-mãe | **6 GB** (8 GB é melhor) |
| Processadores | Sistema → Processador | **2** |
| Disco | Armazenamento | **40 GB** |

Com menos de 6 GB de memória, o Oracle não arranca.

### A2. Dar permissão de administrador ao seu utilizador

No Debian, se definiu uma palavra-passe de *root* na instalação, o seu utilizador não pode
usar `sudo`. Teste:

```bash
sudo whoami
```

**Deve ver:** `root`. Se aparecer `user is not in the sudoers file`, faça o seguinte.

Entre como root (com **hífen**, não til; pede a palavra-passe do **root**):

```bash
su -
```

Junte o seu utilizador ao grupo `sudo` (troque `user` pelo seu nome de utilizador, que é o
que aparece antes do `@` no prompt):

```bash
usermod -aG sudo user
exit
```

**Termine a sessão no Debian e volte a entrar.** Depois, `sudo whoami` deve responder `root`.

### A3. Copiar e colar entre o seu computador e a VM (opcional)

A forma mais simples é abrir este guia no **Firefox dentro da VM** e copiar de lá.

Se preferir copiar do computador principal, instale as *Guest Additions*:

```bash
sudo apt update
sudo apt install -y build-essential dkms linux-headers-$(uname -r) bzip2
```

No menu do VirtualBox: **Dispositivos → Inserir imagem do CD das Adições de Convidado**. Depois:

```bash
sudo mkdir -p /mnt/cdrom
sudo mount /dev/cdrom /mnt/cdrom
sudo sh /mnt/cdrom/VBoxLinuxAdditions.run
sudo reboot
```

Depois de reiniciar: **Dispositivos → Área de transferência partilhada → Bidirecional**.

---

## Parte B: instalar as ferramentas

### B1. Git, Python e utilitários

```bash
sudo apt update
sudo apt install -y git python3 python3-venv python3-pip unzip curl ca-certificates
```

**Deve ver:** termina sem linhas a começar por `E:`.

### B2. Docker (repositório oficial)

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
printf "Types: deb\nURIs: https://download.docker.com/linux/debian\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/docker.asc\n" "$(. /etc/os-release && echo $VERSION_CODENAME)" "$(dpkg --print-architecture)" | sudo tee /etc/apt/sources.list.d/docker.sources
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
```

**Termine a sessão no Debian e volte a entrar** (para o grupo `docker` ficar ativo).

### B3. Confirmar

```bash
docker --version
docker compose version
docker run --rm hello-world
python3 --version
free -h
```

**Deve ver:**
- versões do Docker e do Compose;
- `Hello from Docker!`, **sem usar sudo** (se der `permission denied`, termine a sessão de novo);
- `Python 3.13...`;
- em `free -h`, na coluna *available*, pelo menos **4 GB** (por exemplo `5.1Gi`).

### B4. (Opcional) GitHub CLI, para enviar alterações

Só é preciso para quem vai fazer `git push`. Para apenas usar o projeto, salte para a Parte C.

```bash
sudo apt install -y gh
gh --version
```

Se aparecer `Unable to locate package gh`, use o repositório oficial do GitHub:

```bash
sudo apt install -y wget
sudo mkdir -p -m 755 /etc/apt/keyrings
wget -nv -O- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install -y gh
```

### B5. (Opcional) Ligar o terminal à sua conta GitHub

```bash
gh auth login
```

Responda com as setas e Enter:

1. *Where do you use GitHub?* → **GitHub.com**
2. *Preferred protocol?* → **HTTPS**
3. *Authenticate Git with your GitHub credentials?* → **Yes**
4. *How would you like to authenticate?* → **Login with a web browser**

O terminal mostra um código, por exemplo `! First copy your one-time code: ABCD-1234`.
Abra **https://github.com/login/device** (em qualquer navegador, até no telemóvel), entre
na conta (funciona com "Continue with Google"), cole o código e clique em **Authorize**.

**Deve ver:** `✓ Logged in as ...`

### B6. (Opcional) Identificar-se nos commits

Troque o e-mail pelo da sua conta GitHub (em GitHub → Settings → Emails):

```bash
git config --global user.name "O Seu Nome"
git config --global user.email "SEU-EMAIL@gmail.com"
```

Não mostra nada no ecrã. É normal.

---

## Parte C: obter o projeto

```bash
mkdir -p ~/projetos && cd ~/projetos
git clone https://github.com/Jano-Projects/aviation-otp-observatory.git
cd aviation-otp-observatory
```

**Deve ver:** `ls` mostra `db`, `docs`, `loader`, `README.md`, `tasks.py`...

---

## Parte D: pôr o projeto a funcionar

### D1. Ambiente Python do projeto

O Debian não deixa instalar bibliotecas no Python do sistema. Por isso, o projeto usa um
ambiente próprio, a pasta `.venv`.

```bash
cd ~/projetos/aviation-otp-observatory
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

**Deve ver:** o terminal passa a começar por `(.venv)`, e o último comando termina com
`Successfully installed oracledb-...`.

### D2. Ligar o Oracle

```bash
python tasks.py up
```

**Deve ver no fim:** `==> Database is ready`.
Na primeira vez demora 5 a 15 minutos, porque descarrega a imagem do Oracle. Nas seguintes,
cerca de 30 segundos.

### D3. Instalar o esquema, o utPLSQL e o código PL/SQL

```bash
python tasks.py install
```

**Deve ver, por esta ordem:**
```
==> Creating schema OTP
==> Downloading utPLSQL v3.1.14
==> Installing utPLSQL v3.1.14 (takes about a minute)
==> Installing project objects
...
==> OTP schema installed.
```

### D4. Correr os testes

```bash
python tasks.py test
```

**Deve ver no fim:** `37 tests, 0 failed, 0 errored, 0 disabled, 0 warning(s)`.

### D5. Carregar dados reais da ANAC

```bash
python tasks.py load --from 2026-01 --to 2026-07 --keep-going
```

**Deve ver, por cada mês:**
```
==> Downloading VRA 2026-07
==> Loading VRA_20267.csv
   VRA_20267.csv  month=2026-07  status=SUCCESS  staged=89,517  loaded=89,506  rejected=0  duplicates=11 ...
```

No fim, o `load` constrói também o modelo em estrela de cada mês carregado:
`star schema 2026-07: 89,506 facts`.

O `--keep-going` salta os meses que ainda não estejam publicados.

### D5b. Carregar os nomes das companhias e dos aeroportos

```bash
python tasks.py load-ref
```

Descarrega duas fontes, só na primeira vez: os Dados Estatísticos da ANAC (cerca de 360 MB) e a
lista de aeroportos do OurAirports (cerca de 13 MB). Depois junta-as e dá nome às companhias e aos
aeroportos que aparecem nos voos.

**Deve ver no fim:**
```
   status=SUCCESS  staged=...  merged=...  rejected=...  run_id=...
   names in core: airlines 87/87, airports 289/289
```

Os números exatos dependem dos meses carregados. O que importa é o primeiro número ser igual ao
segundo: todas as companhias e todos os aeroportos ficaram com nome.

### D5c. Reconstruir o modelo em estrela (só se já tinha dados de antes)

Se carregou meses antes de instalar o modelo em estrela (versões anteriores do projeto), construa-o
para todos os meses de uma vez:

```bash
python tasks.py mart
```

**Deve ver:** `7 month(s), 591,381 facts` (com os meses que tiver carregados).

### D6. Ver o resultado

```bash
python tasks.py status
```

**Deve ver:** a lista de carregamentos; por mês, voos, cancelamentos e percentagem de pontualidade;
e quantas companhias e aeroportos têm nome.

### D7. Explorar com SQL (opcional)

Abra o SQL*Plus dentro do contentor:

```bash
python tasks.py sql
```

Experimente (escreva `exit` para sair):

```sql
select orig_icao, count(*) voos, round(100*avg(on_time_15),1) pontualidade
  from core_flight
 where ref_month = date '2026-07-01' and line_type = 'N'
 group by orig_icao having count(*) >= 2000
 order by pontualidade desc;
```

Para usar o **VS Code** (extensão *Oracle SQL Developer*), crie uma ligação com:
utilizador `otp`, palavra-passe do `.env` (`OTP_PASSWORD`), host `localhost`, porta `1521`,
service name `FREEPDB1`.

---

## Parte E: o dia a dia

### Começar a trabalhar (sempre que abre um terminal novo)

```bash
cd ~/projetos/aviation-otp-observatory
source .venv/bin/activate
python tasks.py up
```

### Depois de alterar código PL/SQL

```bash
python tasks.py install
python tasks.py test
```

### Guardar no GitHub

```bash
git add .
git commit -m "descrição curta do que mudou"
git push
```

Depois, veja o resultado dos testes em **Actions** no GitHub.

### Trazer alterações feitas noutra máquina

```bash
git pull
```

### Parar ou apagar a base

```bash
python tasks.py down      # para (os dados ficam guardados)
python tasks.py reset     # apaga TUDO (pede confirmação)
```

---

## Problemas comuns

| Sintoma | Solução |
|---|---|
| `user is not in the sudoers file` | Parte A2. |
| `su: user /home/user does not exist` | Escreveu `su ~` (til). O certo é `su -` (hífen). |
| `permission denied ... docker.sock` | `sudo usermod -aG docker $USER` e termine a sessão. |
| `gh: command not found` | Parte B4 (só necessário para enviar alterações). |
| `error: externally-managed-environment` ou `No module named 'oracledb'` | Falta ativar o ambiente: `source .venv/bin/activate`. |
| `The database is not running` | `python tasks.py up`. |
| `port is already allocated` | No `.env`, mude `ORACLE_PORT=1522` e corra `python tasks.py up`. |
| `ORA-01017: invalid username/password` | Mudou as palavras-passe no `.env` depois de criar a base: `python tasks.py reset`, `up`, `install`. |
| Um mês não descarrega | Ainda não foi publicado. Use `--keep-going`, ou descarregue à mão e use `--file caminho.csv`. |
| A VM fica muito lenta | `python tasks.py down` quando não estiver a usar, ou dê mais memória à VM (A1). |
| Testes vermelhos no GitHub | Abra o passo com ❌ em **Actions** e leia as últimas linhas: normalmente indicam o ficheiro e a linha. |

---

## Checklist

- [ ] `python tasks.py test` mostra `0 failed, 0 errored`
- [ ] pelo menos um mês carregado (`python tasks.py status`)
- [ ] uma consulta SQL a funcionar (`python tasks.py sql`, parte D7)

Para perceber o que cada parte do código faz, continue em [como-funciona.md](como-funciona.md).
