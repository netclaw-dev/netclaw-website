---
title: "Microsoft Teams"
description: "Connect netclaw to personal chats and standard channels in Microsoft Teams."
---

netclaw connects personal chats and standard team channels through the Bot Framework
HTTPS endpoint. Use it when your organization runs on Teams and exposes
`netclawd` through public HTTPS.

## Prerequisites

- netclaw installed and initialized with [`netclaw init`](/cli/init/)
- PowerShell 7 and a checkout of the netclaw release you run
- An Azure subscription with permission to create an Azure Bot resource
- Permission to upload custom Teams apps, or help from a Teams administrator
- A public HTTPS URL with a valid certificate that reaches `/api/messages`
- Public HTTPS privacy and terms pages
- Canonical tenant, team, channel, and user IDs from an authenticated source

## Choose an endpoint

Use a temporary HTTPS tunnel only for a bounded test. Use a stable HTTPS host
for production. Restore the production endpoint after each tunnel test.

See [Exposure modes](/deployment/exposure-modes/) for the supported netclaw
network modes.

Configure a supported non-local exposure mode before registration. A reverse
proxy needs a non-loopback daemon address and explicit `Daemon.TrustedProxies`.

## Register the app and bot

1. [Register a single-tenant application](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app)
   in Microsoft Entra ID.
2. Record the application ID and tenant ID.
3. Create a client secret with the shortest practical expiry.
4. Remove the default Microsoft Graph `User.Read` permission if it exists.
5. Create and [configure an Azure Bot registration](https://learn.microsoft.com/en-us/microsoftteams/platform/bots/how-to/authentication/add-authentication).
6. Select **Single Tenant** as the Azure Bot app type.
7. Use the existing Entra application ID and tenant ID for the bot identity.
8. Enable the Microsoft Teams channel on the Azure Bot resource.
9. Set the messaging endpoint to `https://<public-host>/api/messages`.

Azure Bot accepts one messaging endpoint for personal chats and team channels.
Use the application ID for the Azure Bot, package `AppId`, `ClientId`, and
`BotId`.

Copy the client secret value immediately. Microsoft does not show that value
again. Do not copy the secret ID.

:::caution
Do not add Microsoft Graph permissions. netclaw does not use Graph discovery or
download fallbacks for Teams.

This package does not enable private or shared channels.
:::

## Build the Teams app package

The [package source](https://github.com/netclaw-dev/netclaw/tree/dev/deploy/teams)
contains the manifest template, icons, and build script.

Run this command from the repository root in PowerShell 7.

```powershell
pwsh ./deploy/teams/build-package.ps1 `
  -AppId '<entra-application-id>' `
  -DeveloperName '<operator-name>' `
  -PrivacyUrl 'https://example.com/privacy' `
  -TermsOfUseUrl 'https://example.com/terms' `
  -Version '1.0.0' `
  -OutputPath './artifacts/netclaw-teams.zip'
```

The ZIP contains `manifest.json`, `color.png`, and `outline.png` at its root.
The manifest requests only the `personal` and `team` bot scopes.

Do not commit the generated package. It contains your app ID and policy URLs.
The developer name has a 32-character limit. Increase the semantic version for
every package update.

## Configure netclaw

Store the client secret with [`netclaw secrets`](/cli/secrets/):

```bash
netclaw secrets set Teams.ClientSecret '<client-secret>'
```

Merge this `Teams` object into `~/.netclaw/config/netclaw.json`. Keep unrelated
settings unchanged.

```json
{
  "Teams": {
    "Enabled": true,
    "TenantId": "<tenant-id>",
    "ClientId": "<entra-application-id>",
    "BotId": "<entra-application-id>",
    "AuthenticationMode": "ClientSecret",
    "AllowDirectMessages": false,
    "MentionOnly": true,
    "AllowedTeamIds": ["<canonical-team-id>"],
    "AllowedChannelIds": ["<canonical-channel-id>"],
    "AllowedUserIds": ["<canonical-user-id>"],
    "ChannelAudienceOverrides": [
      {
        "TeamId": "<canonical-team-id>",
        "ChannelId": "<canonical-channel-id>",
        "Audience": "team"
      }
    ]
  }
}
```

Do not add `ClientSecret` to `netclaw.json`. netclaw reads it from the encrypted
secret store or `NETCLAW_Teams__ClientSecret`.

### Configuration fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Enabled` | bool | `false` | Start the Teams channel |
| `TenantId` | string | - | Accepted Entra tenant ID |
| `ClientId` | string | - | Entra application ID |
| `BotId` | string | - | Bare Microsoft App ID for mentions. Do not include `28:`. |
| `AuthenticationMode` | string | `ClientSecret` | Bot credential mode |
| `AllowDirectMessages` | bool | `false` | Accept personal chats |
| `MentionOnly` | bool | `true` | Require a qualified bot mention in team channels |
| `AllowedTeamIds` | string[] | `[]` | Allowed team IDs |
| `AllowedChannelIds` | string[] | `[]` | Allowed channel IDs |
| `AllowedUserIds` | string[] | `[]` | Optional sender filter |
| `ChannelAudienceOverrides` | object[] | `[]` | Team or channel [audience](/security/security-model/) rules |

## Access control

Teams access is default-deny.

- An empty team or channel allow-list rejects all channel messages.
- An empty user allow-list accepts all users in an allowed channel.
- Personal chats require `AllowDirectMessages: true` and an exact
  `AllowedUserIds` match.
- `MentionOnly` requires a qualified bot mention in team channels.
- An unmapped channel uses the `public` audience.

:::caution
Populate `AllowedUserIds` for production. Otherwise, every member of an allowed
channel can address the bot.
:::

Select the bot from the Teams `@` mention menu. Plain text with the bot name is
not a qualified mention.

`AllowedUserIds` uses the Bot Framework sender ID for this bot. It is not the
user's Entra object ID.

`AllowedTeamIds` uses the Teams activity team ID. It can differ from the
Microsoft 365 group object ID.

Obtain IDs through the approved authenticated provisioning process. netclaw
does not learn allow-list values from rejected traffic.

Use `ChannelAudienceOverrides` when an ID contains configuration separators.
Exact team-and-channel entries override team-wide entries.

## Sideload the app

1. Open **Apps** in Microsoft Teams.
2. Open **Manage your apps**.
3. Select **Upload an app**.
4. Select **Upload a custom app**.
5. Upload `netclaw-teams.zip`.
6. Add the app only to approved accounts and teams.

If tenant policy blocks custom uploads, ask a Teams administrator to upload or
approve the package.

Microsoft documents
[custom app upload](https://learn.microsoft.com/en-us/microsoftteams/platform/concepts/deploy-and-publish/apps-upload)
and [organization publication](https://learn.microsoft.com/en-us/microsoftteams/platform/concepts/deploy-and-publish/apps-publish-overview).

## Publish for your organization

1. Build the package with production IDs and policy URLs.
2. Confirm that the manifest contains only `personal` and `team` bot scopes.
3. Upload the package through the Teams admin center.
4. Approve access only for intended users and teams.
5. Keep the bot messaging endpoint on the stable production URL.

Review Microsoft's
[custom app policies](https://learn.microsoft.com/en-us/microsoftteams/teams-custom-app-policies-and-settings)
before organization publication.

## Verify it works

Run the local checks first:

```bash
netclaw doctor
netclaw status
curl http://127.0.0.1:5199/api/health/ready
```

Expect Teams to report `degraded` with the configured-but-unvalidated message.
The readiness endpoint proves only daemon liveness.

The sample configuration disables personal chats. Send one qualified mention
in an allowed channel.

Success requires these results:

- `netclaw doctor` passes.
- The readiness endpoint returns HTTP 200.
- The bot reply appears under the same channel root.
- No unrelated channel root receives the reply.
- The Teams `recv`, `routed`, and `replied` counters increase.

Do not retain tenant IDs, message content, file content, credentials, or tunnel
URLs as test evidence.

## Rotate the client secret

1. Create a new Entra client secret.
2. Store it with `netclaw secrets set Teams.ClientSecret '<new-secret>'`.
3. Restart `netclawd`.
4. Run the health checks.
5. Revoke the old secret after the new secret works.

Keep the old secret active until the checks pass. Never print either secret
during diagnosis.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Teams stays disconnected | The credential or endpoint is invalid | Check `netclaw status`, the secret, and the Azure Bot endpoint |
| A channel message gets no reply | The app, endpoint, tenant, ACL, or mention is wrong | Check the app installation, endpoint, tenant ID, ACL IDs, and structured mention |
| A restricted tool is unavailable | The channel resolved to `public` | Add an exact `ChannelAudienceOverrides` entry |
| An uploaded file is rejected | Teams files are not approved for model dispatch | Remove the upload and send text instead |
| A secret appears in normal config | The secret is in the wrong store | Remove it and rotate it, then use `netclaw secrets set` |

## Roll back

1. Set `Teams.Enabled` to `false`.
2. Restart `netclawd`.
3. Confirm the channel is disabled with `netclaw status`.
4. Block or withdraw the app in the Teams admin center.
5. Revoke the client secret when the rollback is permanent.

Rollback stops new Teams messages. Existing session, approval, reminder, and
delivery records remain.

## Related pages

- [Security model](/security/security-model/) - audience and tool policy
- [`netclaw secrets`](/cli/secrets/) - encrypted secret storage
- [Channel troubleshooting](/channels/troubleshooting/) - shared channel checks

## Resources

- [Teams app manifest schema](https://learn.microsoft.com/en-us/microsoftteams/platform/resources/schema/manifest-schema)
- [Teams app icon requirements](https://learn.microsoft.com/en-us/microsoftteams/platform/concepts/design/design-teams-app-icon-store-appbar)
