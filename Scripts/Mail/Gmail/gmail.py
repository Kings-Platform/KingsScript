#!/usr/bin/env python3
"""Gmail from the command line: send (or draft) a message with attachments, download attachments,
authorize the account. Run through `kings mail`, which provides the virtualenv and the settings.

Settings (config.env): KINGS_MAIL_ACCOUNT, the only address this command acts as, and
KINGS_MAIL_NAME, the sender name. The OAuth client and the token live in the Keychain
(service "kings", accounts KINGS_MAIL_CLIENT and KINGS_MAIL_TOKEN), never in a file."""
import argparse
import base64
import html
import io
import json
import mimetypes
import os
import re
import sys
from email.message import EmailMessage
from pathlib import Path

import keyring
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseUpload

KEYCHAIN_SERVICE = "kings"
CLIENT_SECRET = "KINGS_MAIL_CLIENT"
TOKEN_SECRET = "KINGS_MAIL_TOKEN"
# compose: create drafts and send; readonly: read messages to download their attachments.
SCOPES = ["https://www.googleapis.com/auth/gmail.compose", "https://www.googleapis.com/auth/gmail.readonly"]
GMAIL_LIMIT = 25 * 1024 * 1024


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def account():
    address = os.environ.get("KINGS_MAIL_ACCOUNT", "").strip().lower()
    if not address:
        fail("KINGS_MAIL_ACCOUNT is not set in ~/.kingsScripts/config.env (see the README)")
    return address


def secret(name):
    return os.environ.get(name) or keyring.get_password(KEYCHAIN_SERVICE, name)


def client_config():
    raw = secret(CLIENT_SECRET)
    if not raw:
        fail("No OAuth client in the Keychain: run `kings mail auth --client <client_secret.json>` (see the README)")
    return json.loads(raw)


def save_token(creds):
    keyring.set_password(KEYCHAIN_SERVICE, TOKEN_SECRET, creds.to_json())


# A token past its refresh (Google expires refresh tokens of apps in Testing after 7 days) opens the browser.
def credentials(interactive=True):
    raw = secret(TOKEN_SECRET)
    creds = Credentials.from_authorized_user_info(json.loads(raw), SCOPES) if raw else None
    if creds and creds.valid:
        return creds
    if creds and creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())
            save_token(creds)
            return creds
        except Exception:
            creds = None
    if not interactive:
        return None
    flow = InstalledAppFlow.from_client_config(client_config(), SCOPES)
    creds = flow.run_local_server(port=0, login_hint=account(), open_browser=True)
    save_token(creds)
    return creds


# The token must belong to the configured account; a token for another one is dropped.
def connect():
    gmail = build("gmail", "v1", credentials=credentials(), cache_discovery=False)
    signed_in = gmail.users().getProfile(userId="me").execute()["emailAddress"].lower()
    if signed_in != account():
        keyring.delete_password(KEYCHAIN_SERVICE, TOKEN_SECRET)
        fail(f"Signed in as {signed_in}, expected {account()}. Token removed: run `kings mail auth` and pick the right account.")
    return gmail


def html_to_text(content):
    text = re.sub(r"(?i)<br\s*/?>|</p>|</div>|</li>", "\n", content)
    text = re.sub(r"<[^>]+>", "", text)
    return re.sub(r"\n{3,}", "\n\n", html.unescape(text)).strip()


def build_message(args):
    msg = EmailMessage()
    name = os.environ.get("KINGS_MAIL_NAME", "").strip()
    msg["From"] = f"{name} <{account()}>" if name else account()
    msg["To"] = ", ".join(args.to)
    if args.cc:
        msg["Cc"] = ", ".join(args.cc)
    if args.bcc:
        msg["Bcc"] = ", ".join(args.bcc)
    msg["Subject"] = args.subject
    if args.in_reply_to:
        msg["In-Reply-To"] = args.in_reply_to
        msg["References"] = args.in_reply_to

    body = Path(args.body).expanduser()
    content = sys.stdin.read() if args.body == "-" else body.read_text(encoding="utf-8")
    if args.body != "-" and body.suffix.lower() in {".html", ".htm"}:
        msg.set_content(html_to_text(content))
        msg.add_alternative(content, subtype="html")
    else:
        msg.set_content(content)

    files = [Path(a).expanduser() for a in args.attach]
    missing = [str(f) for f in files if not f.is_file()]
    if missing:
        fail(f"Attachment not found: {', '.join(missing)}")
    if sum(f.stat().st_size for f in files) > GMAIL_LIMIT:
        fail("Attachments exceed 25 MB, Gmail's limit")
    for f in files:
        kind, _ = mimetypes.guess_type(f.name)
        main, sub = (kind or "application/octet-stream").split("/", 1)
        msg.add_attachment(f.read_bytes(), maintype=main, subtype=sub, filename=f.name)
    return msg


def summary(msg, files):
    for field in ("From", "To", "Cc", "Bcc", "Subject"):
        if msg[field]:
            print(f"{field}: {msg[field]}", file=sys.stderr)
    print(f"Attachments: {', '.join(Path(f).name for f in files) or 'none'}", file=sys.stderr)


# Sending goes through a draft so the reply lands in the thread the same way in both modes.
def command_send(args):
    msg = build_message(args)
    summary(msg, args.attach)
    gmail = connect()
    media = MediaIoBaseUpload(io.BytesIO(msg.as_bytes()), mimetype="message/rfc822", resumable=True)
    body = {"message": {"threadId": args.thread}} if args.thread else {}
    draft = gmail.users().drafts().create(userId="me", body=body, media_body=media).execute()
    if args.draft:
        print(f"draft {draft['id']} thread {draft['message']['threadId']}")
        return
    sent = gmail.users().drafts().send(userId="me", body={"id": draft["id"]}).execute()
    print(f"sent {sent['id']} thread {sent['threadId']}")


def parts(payload):
    yield payload
    for part in payload.get("parts", []) or []:
        yield from parts(part)


def safe_name(name):
    return re.sub(r"[/\\:\x00]", "_", name).strip() or "attachment"


def command_attachments(args):
    users = connect().users()
    if args.thread:
        messages = users.threads().get(userId="me", id=args.thread).execute()["messages"]
    else:
        messages = [users.messages().get(userId="me", id=args.message).execute()]
    out = Path(args.out).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    saved = 0
    for message in messages:
        for part in parts(message["payload"]):
            name = part.get("filename")
            attachment_id = (part.get("body") or {}).get("attachmentId")
            if not name or not attachment_id:
                continue
            if args.filter and args.filter.lower() not in name.lower():
                continue
            data = users.messages().attachments().get(userId="me", messageId=message["id"], id=attachment_id).execute()["data"]
            path = out / safe_name(name)
            path.write_bytes(base64.urlsafe_b64decode(data))
            print(path)
            saved += 1
    if not saved:
        fail("No attachments found")


def command_auth(args):
    if args.client:
        client = Path(args.client).expanduser()
        config = json.loads(client.read_text(encoding="utf-8"))
        if "installed" not in config:
            fail("Not a Desktop-app OAuth client JSON (no \"installed\" key)")
        keyring.set_password(KEYCHAIN_SERVICE, CLIENT_SECRET, json.dumps(config))
        print(f"OAuth client stored in the Keychain; you can delete {client}", file=sys.stderr)
    connect()
    print(f"authorized {account()}")


def command_status(args):
    print(f"account: {os.environ.get('KINGS_MAIL_ACCOUNT') or 'not set'}")
    print(f"client: {'keychain' if secret(CLIENT_SECRET) else 'missing'}")
    creds = credentials(interactive=False)
    print(f"token: {'valid' if creds else 'missing or expired (run kings mail auth)'}")


def main():
    parser = argparse.ArgumentParser(prog="kings mail")
    sub = parser.add_subparsers(dest="command", required=True)

    send = sub.add_parser("send", help="Send a message (or only create a draft with --draft)")
    send.add_argument("--to", action="append", required=True)
    send.add_argument("--cc", action="append", default=[])
    send.add_argument("--bcc", action="append", default=[])
    send.add_argument("--subject", required=True)
    send.add_argument("--body", required=True, help=".html/.htm (HTML plus a plain-text part), any other file as text, or - for stdin")
    send.add_argument("--attach", action="append", default=[])
    send.add_argument("--thread", help="Thread id to reply in; the subject must be the thread's, with 'Re: '")
    send.add_argument("--in-reply-to", help="Message-ID of the message being answered, for the recipient's threading")
    send.add_argument("--draft", action="store_true", help="Leave it as a draft instead of sending")
    send.set_defaults(run=command_send)

    attachments = sub.add_parser("attachments", help="Download the attachments of a message or a whole thread")
    target = attachments.add_mutually_exclusive_group(required=True)
    target.add_argument("--thread")
    target.add_argument("--message")
    attachments.add_argument("--out", required=True)
    attachments.add_argument("--filter", help="Only names containing this text (case-insensitive)")
    attachments.set_defaults(run=command_attachments)

    auth = sub.add_parser("auth", help="Authorize the account in the browser")
    auth.add_argument("--client", help="Desktop-app OAuth client JSON to store in the Keychain first")
    auth.set_defaults(run=command_auth)

    status = sub.add_parser("status", help="Account, client and token state")
    status.set_defaults(run=command_status)

    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
