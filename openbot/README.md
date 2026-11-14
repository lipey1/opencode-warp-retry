# OpenBot + opencode-warp-retry (ACP)

O [OpenBot](https://github.com/nightly-labs/openbot) usa o OpenCode como um **agente ACP**. Ele sobe o CLI do OpenCode em um processo próprio, conversa por `stdin`/`stdout` (Agent Client Protocol) e mantém esse processo enquanto precisar — o OpenBot pode reiniciá-lo ao longo do uso.

Isso cria um caminho separado do OpenCode Desktop:

- o processo nasce com o **ambiente do OpenBot**, não com o do seu terminal;
- por isso, abrir o OpenCode Desktop com proxy **não** basta para o OpenBot;
- sem `HTTPS_PROXY`/`HTTP_PROXY`/`ALL_PROXY` no processo ACP, o plugin `warp-retry` carrega **desativado**.

O wrapper [`opencode.cmd`](opencode.cmd) resolve isso: isola os dados do OpenBot, garante o proxy do WARP e registra a decisão em log — sem escrever nada no `stdout`, que é reservado ao ACP.

## Como o OpenBot chama o OpenCode

```text
OpenBot
  └─ cmd.exe /c "<pasta>\opencode.cmd" acp
       └─ opencode-cli.exe acp
            └─ servidor ACP privado (stdin/stdout)
```

O OpenBot resolve o CLI nesta ordem:

1. `OPENBOT_OPENCODE_PATH`, se você definir (recomendado);
2. a cópia gerenciada que o próprio OpenBot baixa, quando existe;
3. `opencode` no `PATH` (via `where.exe`), aceitando `.exe`, `.cmd` e `.bat`.

O wrapper entra como esse `opencode`. Ele repassa todos os argumentos, então `opencode.cmd acp` vira `opencode-cli.exe acp`.

## O que o wrapper faz

1. **Isola dados e estado.** Define `XDG_DATA_HOME` e `XDG_STATE_HOME` para uma pasta própria do OpenBot. A configuração (`~/.config/opencode`) continua compartilhada, então plugin, MCPs, providers e skills são os mesmos do OpenCode Desktop.
2. **Garante o proxy do WARP.** Sonda o proxy de verdade (`https://www.cloudflare.com/cdn-cgi/trace` precisa responder `warp=on`). Se estiver fora, tenta `warp-cli connect` e sonda de novo por até ~10 s. Só então define `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY` e `NO_PROXY`.
3. **Registra a decisão** em `<OPENBOT_OC_HOME>\state\warp-wrapper.log`.

Para `--version` (usado pelo OpenBot ao resolver o provider, com limite de 10 s), o wrapper **não** sonda o WARP: inicia o CLI imediatamente. Versão não precisa de rede.

## Requisitos

- Windows 10/11. Para Linux/macOS, veja a seção no fim.
- OpenBot com o provider **OpenCode** selecionado.
- OpenCode CLI instalado (o `opencode-cli.exe` que o OpenBot usa).
- Cloudflare WARP instalado, logado e em **modo proxy**.
- Plugin `opencode-warp-retry` instalado uma vez.

## Passo a passo

### 1. Instale o plugin (uma vez)

```sh
opencode plugin add opencode-warp-retry
```

O wrapper não define `XDG_CONFIG_HOME`, então essa instalação vale também para o OpenBot. Não copie o `src/index.ts` manualmente se já usou `opencode plugin add`.

### 2. Coloque o WARP em modo proxy

```powershell
& "C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe" mode proxy
& "C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe" connect
```

Confirme que o proxy responde:

```powershell
curl.exe -x http://127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace
```

A saída precisa conter `warp=on`. Se o seu proxy usa outra porta, ajuste `WARP_PROXY_URL` na seção de configuração.

### 3. Copie o wrapper para uma pasta sua

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\bin" | Out-Null
Copy-Item .\openbot\opencode.cmd "$env:USERPROFILE\bin\opencode.cmd"
```

Qualquer pasta serve; `%USERPROFILE%\bin` é só a sugestão usada nos exemplos. Evite uma pasta com `&` ou `%` no nome.

### 4. Aponte o OpenBot para o wrapper

O jeito mais confiável é a variável `OPENBOT_OPENCODE_PATH`:

```powershell
[Environment]::SetEnvironmentVariable(
  "OPENBOT_OPENCODE_PATH",
  "$env:USERPROFILE\bin\opencode.cmd",
  "User"
)
```

Feche o OpenBot por completo e abra de novo. Variáveis de ambiente só são lidas quando o processo nasce.

**Alternativa: `PATH`.** Coloque a pasta do wrapper antes dos outros `opencode`:

```powershell
$dir = "$env:USERPROFILE\bin"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (($userPath -split ';') -notcontains $dir) {
  [Environment]::SetEnvironmentVariable("Path", "$dir;$userPath", "User")
}
```

Reinicie o OpenBot depois. O `OPENBOT_OPENCODE_PATH` é melhor porque o OpenBot também pode baixar uma cópia gerenciada do OpenCode; o caminho explícito é testado antes dela.

### 5. Confirme que está tudo ligado

Rode o wrapper como o OpenBot faria:

```powershell
& "$env:USERPROFILE\bin\opencode.cmd" debug paths
```

O resultado deve mostrar:

```text
data       C:\Users\<voce>\AppData\Local\OpenBot\opencode-cli\data\opencode
config     C:\Users\<voce>\.config\opencode
state      C:\Users\<voce>\AppData\Local\OpenBot\opencode-cli\state\opencode
```

`data`/`state` isolados e `config` compartilhada é exatamente o esperado.

Depois mande uma mensagem no OpenBot e confira o log do plugin:

```powershell
Get-Content "$env:LOCALAPPDATA\opencode-warp-retry\warp-retry.log" -Tail 5
```

A linha precisa ser:

```text
plugin loaded; automatic free-limit retry enabled (proxy: http://127.0.0.1:40000)
```

Se aparecer `plugin loaded but no proxy environment matches`, o wrapper não foi usado ou o WARP estava fora na hora em que o processo ACP nasceu.

## Configuração

Todas as variáveis são opcionais e vão no ambiente do usuário (ou só na sessão, para testar).

| Variável | Padrão | Para que serve |
|---|---|---|
| `OPENBOT_OC_HOME` | `%LOCALAPPDATA%\OpenBot\opencode-cli` | Pasta base de `data` e `state` do OpenCode do OpenBot |
| `OPENBOT_OC_CLI` | auto | Caminho completo do `opencode-cli.exe` |
| `WARP_PROXY_URL` | `http://127.0.0.1:40000` | URL do proxy do WARP |
| `WARP_AUTOCONNECT` | `1` | `0` impede o wrapper de rodar `warp-cli connect` |

Exemplo com caminhos diferentes:

```powershell
[Environment]::SetEnvironmentVariable("OPENBOT_OC_HOME", "D:\OpenBot\opencode-cli", "User")
[Environment]::SetEnvironmentVariable("OPENBOT_OC_CLI", "$env:LOCALAPPDATA\Programs\ai.opencode.desktop\resources\opencode-cli.exe", "User")
```

## Onde ficam as sessões (e como mudar)

Por padrão, o wrapper usa:

```text
%LOCALAPPDATA%\OpenBot\opencode-cli\
  data\
    opencode\
      opencode.db          <- sessões e mensagens do OpenBot
      log\opencode.log     <- log do OpenCode do OpenBot
      repos\
      shell\
      ...
  state\
    opencode\              <- estado do OpenCode do OpenBot
    warp-wrapper.log       <- decisões do wrapper
```

Para mudar, defina `OPENBOT_OC_HOME` e reinicie o OpenBot:

```powershell
[Environment]::SetEnvironmentVariable("OPENBOT_OC_HOME", "D:\OpenBot\opencode-cli", "User")
```

O wrapper cria `data` e `state` no destino. **As sessões existentes não são migradas automaticamente.** Para levar o histórico, feche o OpenBot e copie a pasta antiga antes de trocar a variável:

```powershell
Copy-Item "$env:LOCALAPPDATA\OpenBot\opencode-cli" "D:\OpenBot\opencode-cli" -Recurse
```

Para começar limpo, aponte para uma pasta nova e vazia.

Pontos importantes:

- **Não** aponte o OpenBot para a mesma pasta de dados do OpenCode Desktop. Os dois passariam a dividir sessões, logs e o mesmo banco SQLite; o isolamento existe para evitar essa mistura.
- `~/.config/opencode` continua compartilhada de propósito. É o que faz o plugin, os MCPs e os providers valerem nos dois.
- O cache (`~/.cache/opencode`) também é compartilhado; não é preciso baixar plugin duas vezes.
- O `opencode.db` é do OpenCode do OpenBot. O banco do OpenBot em si (`%APPDATA%\OpenBot\openbot.db`) não muda.

## O proxy, em detalhe

O wrapper define, só no processo do OpenCode:

| Variável | Valor |
|---|---|
| `HTTP_PROXY` | `WARP_PROXY_URL` |
| `HTTPS_PROXY` | `WARP_PROXY_URL` |
| `ALL_PROXY` | `WARP_PROXY_URL` |
| `NO_PROXY` | `localhost,127.0.0.1,::1` |

O `NO_PROXY` é importante: sem ele, o OpenCode tentaria mandar até o tráfego para MCPs locais (por exemplo `127.0.0.1:3000`) pelo WARP.

O plugin **não testa conectividade**; ele só verifica se alguma variável de proxy bate com `proxyUrl`. Quem testa é o wrapper. Se o WARP estiver desligado quando o processo ACP nascer:

1. o wrapper tenta `warp-cli connect`;
2. sonda de novo por até ~10 s;
3. se ainda falhar, inicia **sem proxy** e registra `WARP is unavailable; starting without proxy (retry disabled)`;
4. o plugin carrega desativado **naquele processo**. Um novo processo/sessão do OpenBot tenta de novo.

Se o WARP cair **no meio** de um turno, o erro tende a ser `provider.transport` (rede), não `provider.free-limit`. O plugin atual só reage a limite gratuito; ele não reconecta o WARP em falha de transporte.

## Logs

| Log | Caminho |
|---|---|
| Decisões do wrapper | `%OPENBOT_OC_HOME%\state\warp-wrapper.log` |
| Plugin (retry/rotação) | `%LOCALAPPDATA%\opencode-warp-retry\warp-retry.log` |
| OpenCode do OpenBot | `%OPENBOT_OC_HOME%\data\opencode\log\opencode.log` |

Exemplo do wrapper:

```text
13/11/2026 21:06:50,79 [cli="C:\Users\voce\AppData\Local\Programs\ai.opencode.desktop\resources\opencode-cli.exe"]
13/11/2026 21:06:50,90 [proxy WARP is up (http://127.0.0.1:40000)]
```

Exemplo do plugin quando o limite bate (o pacote npm registra em inglês):

```text
free usage limit on attempt 2; starting a WARP rotation
free usage limit reached: disconnecting WARP (rotation 1/3)
connect: ok=true code=0 Success
WARP ready after 500ms; IP 2a09:bac5:... -> 2a09:bac1:...; settling for 1000ms
WARP reconnected; retrying in 1000ms (attempt 2)
```

Acompanhe ao vivo:

```powershell
Get-Content "$env:LOCALAPPDATA\opencode-warp-retry\warp-retry.log" -Tail 20 -Wait
```

## Verificação rápida

```powershell
# 1. O wrapper responde e isola os caminhos?
& "$env:USERPROFILE\bin\opencode.cmd" debug paths

# 2. O WARP está em modo proxy e conectado?
& "C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe" status
curl.exe -x http://127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace

# 3. O OpenBot está usando o wrapper?
Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" |
  Where-Object { $_.CommandLine -match 'opencode' } |
  Select-Object ProcessId, CommandLine
```

No passo 3, o `CommandLine` deve mostrar o caminho do wrapper, e não diretamente o `opencode-cli.exe`.

## Solução de problemas

| Sintoma | O que fazer |
|---|---|
| `opencode-cli.exe not found` no stderr | Defina `OPENBOT_OC_CLI` com o caminho completo do CLI. |
| O OpenBot continua usando outro CLI | Confirme `OPENBOT_OPENCODE_PATH` no ambiente do usuário e reinicie o OpenBot por completo. |
| `plugin loaded but no proxy environment matches` | O processo ACP nasceu sem o wrapper ou sem WARP. Veja o `warp-wrapper.log`. |
| `WARP is unavailable; ... retry disabled` | O WARP não respondeu em ~10 s. Rode `warp-cli mode proxy` e `warp-cli connect`. |
| `warp-cli connect` falha | O WARP não está logado/registrado. Abra o cliente WARP e conecte uma vez. |
| Proxy conectado, mas `curl -x` falha | O WARP não está em modo proxy, ou a porta não é 40000. Ajuste `WARP_PROXY_URL`. |
| `curl.exe not found` | Windows antigo sem curl. Atualize o Windows ou inicie o OpenCode com as variáveis de proxy manualmente. |
| Sessões do OpenBot e do Desktop misturadas | Defina `OPENBOT_OC_HOME` para uma pasta separada e reinicie o OpenBot. |
| Turno falha com `ECONNREFUSED` | O proxy foi definido, mas o WARP caiu no meio do turno. O plugin não trata `provider.transport`; reconecte o WARP e tente de novo. |
| Continua limitado após rotações | Provável cota por conta, não por IP. Trocar de IP não resolve. |

## Linux/macOS

O OpenBot também roda fora do Windows. O princípio é o mesmo: um script chamado `opencode` que isola `XDG_DATA_HOME`/`XDG_STATE_HOME`, exporta o proxy e executa o CLI real. Exemplo para Linux/macOS (ajuste o caminho do CLI):

```sh
#!/bin/sh
set -eu

OC_HOME="${OPENBOT_OC_HOME:-$HOME/.local/share/openbot/opencode-cli}"
OC_CLI="${OPENBOT_OC_CLI:-opencode}"
PROXY="${WARP_PROXY_URL:-http://127.0.0.1:40000}"

mkdir -p "$OC_HOME/data" "$OC_HOME/state"
export XDG_DATA_HOME="$OC_HOME/data"
export XDG_STATE_HOME="$OC_HOME/state"

if [ "${1:-}" != "--version" ]; then
  if curl -fsS -m 3 -x "$PROXY" https://www.cloudflare.com/cdn-cgi/trace | grep -q 'warp=on'; then
    export HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY" ALL_PROXY="$PROXY"
    export NO_PROXY="localhost,127.0.0.1,::1"
  fi
fi

exec "$OC_CLI" "$@"
```

Salve como `~/bin/opencode`, dê `chmod +x` e aponte `OPENBOT_OPENCODE_PATH` para ele. No Linux/macOS o caminho pode ser exportado no `~/.profile`/`~/.zshrc`; reinicie o OpenBot depois.

## Limites

- Vale para o OpenBot quando o provider é **OpenCode**. Codex, Claude, Grok puro e agentes ACP customizados não passam por este wrapper.
- O OpenCode limita a aproximadamente **10 tentativas físicas por requisição**; o plugin rotaciona dentro desse teto.
- Rotacionar o WARP interrompe brevemente todo tráfego que usa WARP na máquina.
- O wrapper não altera o proxy do sistema: as variáveis valem só para o processo do OpenCode.
- O plugin não corrige cota por conta. Se o limite é da conta e não do IP, trocar de IP não ajuda.

## Arquivos

```text
openbot/opencode.cmd          wrapper para Windows
openbot/README.md             este guia
openbot/README.en.md          English version
```

Volte para o README principal: [README.pt-BR.md](../README.pt-BR.md).
