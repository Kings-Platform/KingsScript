# Mail (Gmail)

`kings mail` sends Gmail messages with attachments and downloads attachments, from the terminal or
from an AI agent. It exists because email connectors usually can't attach a local file (a CV, a
report): this command can.

#### Index

- [Commands](#commands)
- [Setup](#setup)
- [How it works](#how-it-works)
- [Security](#security)

## Commands

| Command | What it does |
|---|---|
| `kings mail send --to <addr> --subject "<s>" --body <file> [options]` | Sends the message and prints `sent <message id> thread <thread id>` |
| `kings mail attachments --thread <id> \| --message <id> --out <dir> [--filter <text>]` | Saves the attachments of one message, or of every message in a thread, and prints each path |
| `kings mail auth [--client <client_secret.json>]` | Authorizes the account in the browser; `--client` stores the OAuth client first |
| `kings mail status` | Configured account, whether the OAuth client is stored, whether the token is valid |

`send` options:

| Option | Meaning |
|---|---|
| `--to`, `--cc`, `--bcc` | Recipients; repeat the flag for several |
| `--body <file>` | `.html`/`.htm` goes as HTML with a plain-text part; any other file goes as text; `-` reads text from stdin |
| `--attach <file>` | Attachment; repeat for several (25 MB in total, Gmail's limit) |
| `--thread <id>` | Reply inside this thread. The subject must be the thread's, with `Re: ` |
| `--in-reply-to <Message-ID>` | The answered message's `Message-ID` header, so the recipient's client threads it too |
| `--draft` | Leave it as a draft in Gmail instead of sending; prints `draft <id> thread <id>` |

```bash
kings mail send --to recruiter@company.com --subject "iOS Developer - Jane Doe" \
  --body ~/mail/application.html --attach ~/CV/JaneDoe_CV.pdf

kings mail attachments --thread 19ce8fc963b19e91 --out ~/Downloads/contract --filter .pdf
```

The summary (from, to, subject, attachments) goes to stderr before anything is sent, so it lands in
the log and in an agent's transcript.

## Setup

Once per machine. You need a Google account and about 10 minutes.

### 1. Settings

In `~/.kingsScripts/config.env`:

```bash
KINGS_MAIL_ACCOUNT="you@gmail.com"   # the only account the command acts as
KINGS_MAIL_NAME="Your Name"          # sender name shown to recipients
```

### 2. Google Cloud project

At [console.cloud.google.com](https://console.cloud.google.com), signed in with that account:

1. Create a project (any name).
2. **APIs & Services → Library**: enable the **Gmail API**.
3. **Google Auth Platform → Branding**: user type **External**; app name and contact emails.
4. **Audience**: add your address as a **test user**.
5. **Data Access**: add the scopes `https://www.googleapis.com/auth/gmail.compose` and
   `https://www.googleapis.com/auth/gmail.readonly`.
6. **Clients → Create client**: type **Desktop app**; download the JSON.

### 3. Authorize

```bash
kings mail auth --client ~/Downloads/client_secret_XXXX.json
```

- The first run creates a Python environment in `~/.kingsScripts/venvs/mail` (needs `python3`).
- The browser opens: pick the configured account. "Google hasn't verified this app" is expected for
  your own app: **Continue**.
- The client and the token go to the Keychain. Delete the downloaded JSON afterwards.
- `kings mail status` confirms it.

### Weekly re-authorization

An app left in **Testing** gets refresh tokens that Google expires after **7 days**. The next
command after that opens the browser again; one click and it continues. Publishing the app removes
the limit but asks for a home page and a privacy policy on a verified domain, which rarely pays off
for personal use.

## How it works

| Piece | Role |
|---|---|
| `mail.sh` | Checks the subcommand, keeps the virtualenv in sync with `requirements.txt`, runs `gmail.py` |
| `gmail.py` | Gmail API: builds the MIME message, sends through a draft, reads attachments |
| `requirements.txt` | `google-api-python-client`, `google-auth-oauthlib`, `keyring` |

- **Sending goes through a draft** (`drafts.create`, then `drafts.send`): the same path serves
  `--draft`, and a reply with `--thread` lands in the thread in both modes.
- **Account check:** every run compares the signed-in address with `KINGS_MAIL_ACCOUNT`. A token for
  another account is dropped and the command stops.

## Security

- **No secret in a file.** The OAuth client and the token live in the macOS Keychain, service
  `kings`, accounts `KINGS_MAIL_CLIENT` and `KINGS_MAIL_TOKEN` — the same store as
  `kings secret`. An environment variable with that name wins, as in `secret_get`.
- **Scopes:** `gmail.compose` creates drafts and sends; `gmail.readonly` reads messages for
  `attachments`. Nothing deletes, archives or changes labels.
- **Revoke:** [myaccount.google.com/permissions](https://myaccount.google.com/permissions), then
  `kings secret delete KINGS_MAIL_TOKEN`.
- An agent should send only what its user approved: the command sends right away, so the approval
  belongs before the call (or use `--draft` and let the user send from Gmail).
