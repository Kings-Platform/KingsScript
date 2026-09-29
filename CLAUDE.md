# KingsScript — convenções do repo

Ponto de partida: [docs/Roadmap.md](docs/Roadmap.md) (decisões e fases). Uso e contrato das camadas: [README.md](README.md).

## Código

- Código, comentários e README em **inglês**. Docs de decisão em `docs/` em português.
- Shebang `#!/bin/bash` e compatível com **bash 3.2**: nada de `declare -A`, `mapfile`, `${var,,}`, `local -n`. Testar com `/bin/bash`, não com o bash do Homebrew.
- `printf` em vez de `echo -e`.
- Script que roda por `exec` precisa do bit de execução (`chmod +x`), inclusive nas camadas.
- Mensagem pro usuário via `print_*` (vai pro stderr e pro log). Saída que é o resultado do comando (tabela, lista) vai pro stdout com `printf`.
- Estado da máquina só em `$KINGS_HOME` (`~/.kingsScripts`), nunca dentro do repo.
- Testes manuais sempre com `KINGS_HOME` e `HOME` apontando pra pasta temporária, pra não mexer no `.zshrc` e no `~/.gitconfig` reais.

## Git

- Trunk-based: branch curta a partir do `main` (`feature/...`, `fix/...`).
- A IA faz os commits; o Gui revisa no GitHub Desktop e faz o push.
- Mensagem de commit curta e direta, em inglês. Descrição só quando necessário, em bullets.
