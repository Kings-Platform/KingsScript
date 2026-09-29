# KingsScript — Roadmap

Central única de scripts pessoais do Gui, acionada por `kings <comando> [args]`. Junta duas origens:

- **Kings-Script** (Santander, 2023–2025): biblioteca comum rica (logs, prints, notificações, timer, segredo via Keychain) e scripts presos ao ambiente do banco.
- **KingsScripts** (Novibet, 2026): dispatcher com mapa explícito, hooks globais de Git, cache, FigParser, graph/docs-check, VPN, Slack.

O core é genérico e serve de **base pra qualquer contexto**: cada empresa (ou projeto pessoal, como a Maria Cacau) vira uma **camada** em repo próprio, que usa a biblioteca do core.

## Decisões

| # | Decisão | Por quê |
|---|---|---|
| 1 | **Core + camadas em repos separados**, não fork nem worktree | Worktree é branch do mesmo repo: o código da empresa iria pro remote pessoal. Fork diverge e disputa o mesmo `case` do dispatcher a cada atualização |
| 2 | **Dispatcher com `case` explícito**, um por repo | Mantém a decisão original (erro claro pra comando inexistente). Camada responde `127` pra comando que não é dela — é o código de "command not found" do shell, e separa "não é comigo" de "é comigo e falhou" |
| 3 | **Hooks de Git por camada**, core sem hooks por enquanto | Cada camada adiciona os seus em `hooks/<nome>.sh`. Se o core precisar, entra depois |
| 4 | **Estado da máquina em `~/.kingsScripts/`** (config, cache, logs, git-hooks, layers) | Fora do repo: código e estado não se misturam. Substitui o `cache.txt` dentro do repo |
| 5 | **Repo fica onde foi clonado**; o instalador só registra o caminho | Editar e usar é o mesmo código, sem sincronizar cópia |
| 6 | **Log por dia**: `~/.kingsScripts/logs/AAAA-MM-DD.log`, linha com hora, comando e PID | Um arquivo por execução espalhava demais. PID separa execuções simultâneas no mesmo arquivo |
| 7 | **Logs do mês anterior viram `AAAA-MM.zip`** na virada do mês | Mantém o histórico sem acumular arquivo solto |
| 8 | **Checkup genérico ao abrir o terminal** (estilo Oh My Zsh), em background | Manutenção periódica (zip de logs hoje; update amanhã) sem comando manual. Cada tarefa roda no máximo uma vez por período, controlado pelo cache |
| 9 | **Segredo nunca em arquivo**: variável de ambiente ou Keychain | Herdado do `kaccess` antigo |
| 10 | **Código, comentários e README em inglês**; docs de decisão (esta pasta) em português | |
| 11 | **Bash 3.2** (`/bin/bash` do macOS) | É o que roda nos hooks do Git; nada de array associativo, `mapfile` ou `${var,,}` |
| 12 | **Camada da Novibet**: repo privado no GitHub da empresa. **Camada do Santander**: repo no GitHub pessoal, a partir do histórico do Kings-Script4 | |
| 13 | **Trunk-based**: branch curta a partir do `main` | |

## Fases

| Fase | O quê | Status |
|---|---|---|
| 0 | Base do repo: `.gitignore`, docs, convenções | ✅ |
| 1 | Core lib (`Scripts/Core/`): env/config, log diário, print, timer, notify, secrets, cache, layers | ✅ |
| 2 | Dispatcher + comandos embutidos: `help`, `layer`, `hooks`, `checkup`, `secret` | ✅ |
| 3 | `install.sh` / `uninstall.sh` idempotentes, template de camada | ✅ |
| 4 | Portar comandos genéricos: `git-swiftformatstaged`, `git-prreview`, `fig-parse`/`fig-check`, `slack-test`, `docs-check`, `graph` (caminhos via config), `xcode-simulator`, `xcode-deeplink`, `git-deletebranch`, `install-tabby`, `install-gem` | ⏳ |
| 5 | Camada `novibet`: hooks (branch-hook, autologin, xcode27, precommit-guard), `vpn`, docs de demanda. Migrar a máquina de trabalho e só então apagar o `~/Repos/KingsScripts` e o `~/.git-hooks-global` antigos | ⏳ |
| 6 | Camada `santander` a partir do histórico do Kings-Script4 (reorganização no formato de camada por cima) | ⏳ |
| 7 | Camada `maria-cacau`, quando surgir o primeiro script | ⏳ |
| — | GitHub Actions (ShellCheck + smoke test) | Depois, mas considerado desde já |
| — | Checkup de atualização do próprio KingsScript | Futuro |

## Bugs da lib antiga corrigidos no port

- `check_if_file_exists` imprimia `true` e depois `false`.
- Cores com `echo "\033..."` só funcionavam porque os scripts eram chamados com `sh`; agora é `printf`.
- `send_notification` retornava os códigos invertidos.
- `finish_script` saía com `exit 1` em caso de sucesso.
