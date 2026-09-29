# Git hooks

Any `<hook>.sh` here (executable) runs for that git hook in every repository, with git's own
arguments and stdin: `post-checkout.sh`, `pre-commit.sh`, `pre-push.sh`, and so on.

Hooks run for all repositories on the machine, so a hook that only applies to one project
should check `git config --get remote.origin.url` first and exit 0 otherwise.

`kings hooks off` turns every layer hook off at once.
