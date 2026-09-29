# KingsScript — convenções do repo

Uso e contrato das camadas: [README.md](README.md). Decisões e fases ficam em `docs/`, que é local e fica fora do git (o repo é feito pra poder ser público, e esses docs citam contexto privado). Se a pasta existir, `docs/Roadmap.md` é o ponto de partida.

## Código

- Código, comentários e README em **inglês**. Docs de decisão em `docs/` (local) em português.
- Nada commitado cita empresa, cliente ou pessoa: contexto privado só em `docs/`.
- Shebang `#!/bin/bash` e compatível com **bash 3.2**: nada de `declare -A`, `mapfile`, `${var,,}`, `local -n`. Testar com `/bin/bash`, não com o bash do Homebrew.
- **Estrutura de todo script:** cada etapa numa função com nome de ação e um comentário de uma linha em cima; no fim do arquivo, as funções chamadas em ordem, lendo como roteiro. Script com subcomandos termina num `case` que chama as funções.
- Comentário de uma linha nos trechos não óbvios (o porquê, não o quê); sem docstring longa.
- `printf` em vez de `echo -e`.
- Script que roda por `exec` precisa do bit de execução (`chmod +x`), inclusive nas camadas.
- Todo comando tem que funcionar pra humano e pra IA: entrada por argumento, sem prompt (se precisar, avisar na linha do `help`), exit `0`/`1` (`127` só pra "não é meu").
- Mensagem pro usuário via `print_*` (vai pro stderr e pro log). Saída que é o resultado do comando (tabela, lista) vai pro stdout com `printf`.
- Estado da máquina só em `$KINGS_HOME` (`~/.kingsScripts`), nunca dentro do repo.
- Testes manuais sempre com `KINGS_HOME` e `HOME` apontando pra pasta temporária, pra não mexer no `.zshrc` e no `~/.gitconfig` reais.

## Git

- Trunk-based: branch curta a partir do `main` (`feature/...`, `fix/...`).
- A IA faz os commits; o Gui revisa no GitHub Desktop e faz o push.
- Mensagem de commit curta e direta, em inglês. Descrição só quando necessário, em bullets.
