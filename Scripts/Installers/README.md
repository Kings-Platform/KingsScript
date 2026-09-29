# Installers

Installs tools on machines without admin rights — where Homebrew or `/Applications` aren't
an option. Everything goes to user folders.

| Command | Installs to | Notes |
|---|---|---|
| `kings install-tabby` | `~/Apps/Tabby.app` (`KINGS_APPS_DIR`) | Latest release for this Mac's architecture; also adds a `.zshrc` block that makes Terminal hand off to Tabby |
| `kings install-gem <gem> [version]` | `~/.gem` (`--user-install`) | Follows RubyGems' "install version X first" suggestions; pinned versions in [`Gem/pinned-dependencies.txt`](Gem/pinned-dependencies.txt) |

> [!NOTE]
> User-installed gems need their `bin` folder on the `PATH`:
> `export PATH="$(ruby -e 'print Gem.user_dir')/bin:$PATH"`.
