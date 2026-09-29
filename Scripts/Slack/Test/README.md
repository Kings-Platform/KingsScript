# Slack test

`kings slack-test [channel_id]` reads the channel's last message and posts one back quoting it —
a quick proof that the app's token and scopes work.

## Setup

```bash
# 1. Create the app from manifest.yaml at api.slack.com/apps and install it to the workspace

# 2. Store the Bot User OAuth Token (xoxb-...) in the Keychain
kings secret set SLACK_BOT_TOKEN

# 3. Invite the bot to the channel (in Slack: /invite @KingsBot), then run
kings slack-test C0123456789
```

| Setting | Where |
|---|---|
| Token | `SLACK_BOT_TOKEN` — env var or Keychain |
| Default channel | `KINGS_SLACK_CHANNEL` in `~/.kingsScripts/config.env` |

> [!NOTE]
> Messages posted by the app show up as sent by an app, not by you — worth knowing before
> using it to post in a team channel.

Requirements: `curl`, `jq`.
