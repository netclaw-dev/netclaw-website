---
title: "Microsoft Teams"
description: "Connect netclaw to Teams personal chats, channels, and approved Group Chats."
---

Connect netclaw to Teams through an Azure Bot for personal chats, standard channel threads, and approved Group Chats. It supports approval cards, proactive replies and reminders, bounded image handling, and Graph-backed discovery and group authorization.

:::note
This guide covers the current `dev` implementation. Use a netclaw build that includes it; earlier releases may not.
:::

Teams transports normal messages, and Microsoft Graph handles directory discovery and group-membership checks. netclaw enforces tenant, ACL, session, audience, and tool policies before every model dispatch.

## Before you begin

- A working netclaw installation and a public HTTPS endpoint for `netclawd`
- A valid TLS certificate for that endpoint
- Public HTTPS privacy-policy and terms-of-use URLs
- A Microsoft Entra tenant and permission to register an application
- An active Azure subscription, plus permission to create or use a resource group and an Azure Bot resource
- Teams custom-app deployment capability, or a Teams administrator who has it
- An Entra administrator who can grant Graph application consent when you use directory features

An Azure subscription is required because Azure Bot is an Azure resource. Use a short-lived HTTPS tunnel only for testing; production needs a stable public endpoint. See [Exposure modes](/deployment/exposure-modes/) for netclaw network configuration.

## How it fits together

```text
Microsoft Teams
        |
Azure Bot / Bot Framework endpoint
        |
POST /api/messages
        |
Microsoft Teams SDK 2.x
        |
netclaw Teams adapter
        |
sessions / approvals / tools / reminders
```

Azure Bot and the Teams SDK carry message transport. Graph does not carry normal Teams messages. It resolves directory labels and checks configured Entra group membership.

Standard Team channels and threads are supported. Private and shared channels, meetings, calling, tabs, and video are not. The package supports personal, team, and Group Chat scopes.

## Create the Azure and Entra resources

| Azure item | Requirement | Example |
| --- | --- | --- |
| Subscription | Active Azure subscription | `Production subscription` |
| Resource group | Contains the bot | `rg-netclaw-teams` |
| Azure Bot | Single-tenant bot using the netclaw Entra app | `netclaw-teams` |
| Location | Azure Bot location | `Global` |
| Pricing tier | A suitable Azure Bot tier | `F0` is a common starting tier |
| Teams channel | Enabled on the Azure Bot | Microsoft Teams |
| Messaging endpoint | Public netclaw ingress | `https://netclaw.example.com/api/messages` |

### Register one Entra application

1. [Register a single-tenant application](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app).
2. Record its tenant ID and application (client) ID.
3. Create a client secret with the shortest practical lifetime. Copy the **secret value**, not its identifier. Microsoft documents [client-secret creation and rotation](https://learn.microsoft.com/en-us/entra/identity-platform/how-to-add-credentials).
4. Remove the default delegated `User.Read` permission if Entra added it. netclaw does not require it.

Use the application/client ID as the Azure Bot Microsoft App ID and `Teams.ClientId`. Set `Teams.BotId`, the package `id` and `botId`, and `webApplicationInfo.id` to the same value. `BotId` lets netclaw recognize structured bot mentions; it is not a separate Graph credential.

:::caution
**The number one setup mistake is storing `ClientSecret` in `netclaw.json`.** Use netclaw's encrypted secret store. The secret overlay or `NETCLAW_Teams__ClientSecret` are also supported. The same credential serves Azure Bot and Graph; netclaw does not need or store a second Graph secret or Graph access tokens.
:::

### Create the Azure Bot

1. Create or select `rg-netclaw-teams`.
2. Create an Azure Bot and select the single-tenant application model.
3. Use the existing Entra application/client ID and tenant ID.
4. Enable the **Microsoft Teams** channel.
5. Set the messaging endpoint to `https://<public-netclaw-host>/api/messages`, for example `https://netclaw.example.com/api/messages`.
6. Confirm the endpoint is publicly reachable over valid TLS.

Follow Microsoft's [Azure Bot resource guide](https://learn.microsoft.com/en-us/azure/bot-service/abs-quickstart?view=azure-bot-service-4.0) for the current portal workflow.

## Grant the right permissions

Teams/Bot transport, Graph application permissions, and Teams resource-specific consent (RSC) are separate security surfaces. Do not put RSC entries in Entra's Graph permission list.

### Microsoft Graph application permissions

Grant these **application** permissions and admin consent when using discovery or group authorization. A manual canonical-ID setup without group authorization works without them; see the [Microsoft Graph permission reference](https://learn.microsoft.com/en-us/graph/permissions-reference) when granting consent.

| Permission | Admin consent | netclaw use |
| --- | ---: | --- |
| `Team.ReadBasic.All` | Yes | Discover Teams and display Team metadata |
| `Channel.ReadBasic.All` | Yes | Discover channels and display names and descriptions |
| `User.Read.All` | Yes | Discover users and their canonical Entra identities |
| `GroupMember.Read.All` | Yes | Discover groups and check group membership for authorization |
| `Chat.ReadBasic.All` | Yes, optional | Discover Group Chat titles and basic metadata |

`Chat.ReadBasic.All` enables friendly Group Chat discovery. You do not need it when entering a canonical Group Chat ID manually. It does not grant chat-message access or prove that the app is installed in a chat.

netclaw does not require delegated `User.Read`, `Directory.Read.All`, `Chat.Read.All`, `ChatMessage.Read.All`, `Files.Read.All`, or `Sites.Read.All` for this feature.

### Teams resource-specific consent

The generated package requests these **Application / RSC** permissions:

| Permission | Scope | Purpose |
| --- | --- | --- |
| `ChannelMessage.Read.Group` | Installed Team | Lets Teams deliver the channel messages needed for an approved human to continue an established bot thread without another mention |
| `ChatMessage.Read.Chat` | Installed Group Chat | Supports packaged-app message delivery in approved Group Chats |

RSC is defined in the Teams manifest, not in Entra. Teams asks the appropriate resource owner for consent when the app is added or upgraded in a Team or chat. See Microsoft's [RSC consent guidance](https://learn.microsoft.com/en-us/microsoftteams/manage-consent-app-permissions).

Before dispatch, netclaw checks the authenticated tenant, Team, channel or chat, principal, ACL, mention policy, root or thread, and audience. RSC does not bypass those checks.

## Build and install the Teams app

Clone or download the matching netclaw source checkout that contains [`deploy/teams`](https://github.com/netclaw-dev/netclaw/tree/dev/deploy/teams), then run the package script from that repository root. It uses built-in PowerShell archive support, so Windows PowerShell 5.1 and PowerShell 7 are both suitable.

```powershell
$BuildPackage = @{
    AppId = '00000000-0000-0000-0000-000000000000'
    DeveloperName = 'Example Operator'
    PrivacyUrl = 'https://example.com/privacy'
    TermsOfUseUrl = 'https://example.com/terms'
    OutputPath = './artifacts/netclaw-teams.zip'
    Version = '1.0.0'
}

./deploy/teams/build-package.ps1 @BuildPackage
```

The ZIP root contains `manifest.json`, `color.png`, and `outline.png`. The manifest requests `personal`, `team`, and `groupchat` bot scopes plus both RSC permissions above. Because it includes your application ID and policy URLs, do not commit it. Increase the semantic `Version` for every upgrade so Teams recognizes the update and requests any new manifest permissions.

### Test or deploy

For development, sideload the ZIP if tenant policy permits custom app uploads. For organization deployment, upload and approve the package through the Teams admin center, then make it available only to intended users and Teams. Policy can block user sideloading.

Making the package available does not install it into a conversation. Add it personally for a personal-chat test, add it to each approved Team for channel use, and add it to each approved Group Chat for Group Chat use. Teams asks the appropriate resource owner for RSC consent at that installation or upgrade. Use Microsoft's [custom-app upload guide](https://learn.microsoft.com/en-us/microsoftteams/platform/concepts/deploy-and-publish/apps-upload) for testing and its [admin-center policy guide](https://learn.microsoft.com/en-us/microsoftteams/teams-custom-app-policies-and-settings) for organization rollout.

## Configure netclaw

Start in the TUI:

```text
netclaw config
  -> Channels
  -> Microsoft Teams
```

Configure the tenant ID, application/client ID, Bot ID, and masked client secret. The TUI supports discovery, access management, attachment configuration, Group Chat discovery, and manual entry of canonical IDs.

Names, UPNs, and mail addresses shown by discovery are presentation metadata. netclaw persists and authorizes canonical IDs only. Use the manual ID path when Graph discovery is unavailable.

Store the secret separately:

```bash
netclaw secrets set Teams.ClientSecret '<client-secret>'
```

### Send the first message

For a minimal setup, enter canonical IDs manually and skip Graph permissions. Grant Graph permissions only when you need discovery or Entra group authorization.

1. Enable Teams and save the connection in the TUI.
2. Add one allowed user, then configure either personal chats or one Team and one channel.
3. Add the packaged app to that personal scope, Team, or Group Chat.
4. Wait for the coordinated daemon reload after the saved configuration, then send a message from the allowed user.

| To allow | Configure |
| --- | --- |
| Personal chat | `AllowDirectMessages=true` and a global `AllowedUserIds` or `AllowedGroupIds` grant |
| Standard channel | The canonical Team ID in `AllowedTeamIds`, its canonical channel ID in `AllowedChannelIds`, and an allowed principal when you want sender restrictions |
| Group Chat | `AllowGroupChats=true`, the canonical chat ID in `AllowedGroupChatIds`, and a global allowed principal |

For a new channel root or any Group Chat message with `MentionOnly=true`, select the bot from Teams' `@` mention picker. Typing its display name is not a structured bot mention.

### Users, groups, and channel access

The canonical user identity is normally the authenticated Teams `aadObjectId` - the Entra object ID. netclaw falls back to the Bot Framework sender ID only when that identity is absent. Obtain users through authenticated directory discovery or the TUI.

| Setting | What it controls |
| --- | --- |
| `AllowedUserIds` | Global allowed Entra user object IDs |
| `AllowedGroupIds` | Global allowed Entra group object IDs |
| `ChannelAccessOverrides` | Exact Team-and-channel principal grants that combine with global grants |
| `ChannelAudienceOverrides` | Audience and tool-policy classification for a Team or channel |

Global and matching channel-specific grants combine. Once a global or matching channel-specific principal rule exists, a sender must match one of them. A group match never bypasses tenant, Team, channel, mention, root, or audience policy. Graph failures deny group-derived authorization. An explicit allowed user does not need a group lookup.

`ChannelAudienceOverrides` changes the [audience and tool policy](/security/security-model/). `ChannelAccessOverrides` adds channel-specific principal grants. They are not interchangeable.

### Group Chats

Group Chat ingress is disabled by default. Enable it here:

```text
netclaw config
  -> Channels
  -> Microsoft Teams
  -> Group Chat ingress
```

Each Group Chat also needs an exact tenant match, an ID in `AllowedGroupChatIds`, and an authorized global user or verified global group member. With `MentionOnly=true`, every Group Chat message needs a structured bot mention.

Ingress, chat authorization, and saved chat IDs are independent. Enabling ingress does not authorize a chat, adding a chat does not enable ingress, and disabling ingress preserves saved IDs.

For title discovery, open:

```text
Add a channel or Group Chat
  -> Group Chat
  -> Group Chat name
```

Search matches partial or full titles without case sensitivity. Because Graph has no tenant-wide chat-title search, netclaw performs bounded metadata discovery and deduplicates canonical chat IDs. Searches can take time in large tenants; you can stop and resume them. An incomplete search does not prove a chat is missing - enter its canonical ID through the advanced path.

### Mention and thread behavior

Keep `MentionOnly=true`. A new Team channel root needs a genuine structured bot mention. After an approved human establishes that root, RSC-backed delivery can allow that same human to continue the thread without mentioning the bot again. Unknown roots, other senders, and unapproved users still do not dispatch a model turn.

Personal chats do not use channel-root mention semantics. Group Chats do: with `MentionOnly=true`, every Group Chat message requires a structured mention.

### Attachments and images

`AllowAttachments` defaults to `false`. When enabled, netclaw accepts image candidates only after bounded trust checks, download, and verification. PNG, JPEG, GIF, and WebP reach image-capable models only when active policy permits it.

Unsafe or ambiguous attachments fail closed. Verified but unsupported image formats can remain available only as paths. Ordinary channel and Group Chat files are more restricted than image ingress. Do not add broad Graph file permissions as a workaround.

## Manual configuration reference

Use the TUI first. This reference is for scripted or headless installs; keep the secret out of normal JSON.

```json
{
  "Teams": {
    "Enabled": true,
    "TenantId": "<tenant-id>",
    "ClientId": "<entra-application-id>",
    "BotId": "<entra-application-id>",
    "AuthenticationMode": "ClientSecret",
    "AllowDirectMessages": false,
    "AllowGroupChats": false,
    "AllowAttachments": false,
    "MentionOnly": true,
    "AllowedTeamIds": [],
    "AllowedChannelIds": [],
    "AllowedGroupChatIds": [],
    "AllowedUserIds": [],
    "AllowedGroupIds": [],
    "ChannelAudiences": {},
    "ChannelAudienceOverrides": [],
    "ChannelAccessOverrides": []
  }
}
```

| Field | Default | Description |
| --- | --- | --- |
| `Enabled` | `false` | Starts the Teams channel |
| `TenantId` | - | Accepted Entra tenant ID |
| `ClientId` | - | Entra application/client ID |
| `BotId` | - | Bare Microsoft App ID used for mentions. Do not include `28:` |
| `AuthenticationMode` | `ClientSecret` | Supported credential mode |
| `AllowDirectMessages` | `false` | Allows personal chats from authorized global principals |
| `AllowGroupChats` | `false` | Enables Group Chat ingress after its other gates pass |
| `AllowAttachments` | `false` | Enables bounded attachment handling |
| `MentionOnly` | `true` | Requires structured mentions under the channel and Group Chat rules above |
| `AllowedTeamIds` | `[]` | Allowed canonical Teams IDs |
| `AllowedChannelIds` | `[]` | Allowed canonical channel IDs |
| `AllowedGroupChatIds` | `[]` | Allowed canonical Group Chat IDs |
| `AllowedUserIds` | `[]` | Global allowed principal IDs |
| `AllowedGroupIds` | `[]` | Global allowed Entra group object IDs |
| `ChannelAudiences` | `{}` | Legacy dictionary of canonical Team or Team/channel keys to an audience |
| `ChannelAudienceOverrides` | `[]` | Team or channel audience overrides |
| `ChannelAccessOverrides` | `[]` | Exact channel principal grants that combine with global grants |

`ChannelAudienceOverrides` is the delimiter-safe audience form. Use it when a canonical ID contains configuration path delimiters; an exact Team-and-channel entry takes precedence over a Team-wide entry. Empty Team or channel allow-lists reject channel traffic. An allowed channel uses legacy channel-only authorization only when no global or matching channel-specific principal rule exists. Personal and Group Chats still require a global principal grant.

## Verify the integration

Run the local checks after configuration, package changes, or secret rotation:

```bash
netclaw doctor
netclaw status
curl http://127.0.0.1:5199/api/health/ready
```

Run the readiness command on the daemon host or inside its container or network namespace. For a remote deployment, use that deployment's local health-check path instead. The readiness endpoint proves only that the daemon is live. Teams remains configured but unvalidated in this release.

Then test the enabled surfaces:

1. Send a personal message from an allowed user if personal chats are enabled.
2. Mention the bot in a new root in an approved channel. Confirm the reply stays in that root.
3. Reply in that thread without a mention as the same approved user. Confirm that the bot continues the thread, then confirm that it ignores an unmentioned new root.
4. In an enabled, approved Group Chat, send a structured bot mention from an allowed principal.
5. Trigger a safe, non-destructive action that needs approval and confirm the Teams Adaptive Card renders.

Check that the Teams `recv`, `routed`, and `replied` counters advance. Do not retain message bodies, identifiers, endpoints, tokens, or secrets as test evidence.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Azure Bot cannot reach netclaw | Wrong endpoint, reverse proxy, or TLS | Set the exact `/api/messages` HTTPS endpoint and verify certificate and proxy configuration |
| Connector is disconnected | Invalid tenant, client ID, Bot ID, or secret | Compare the Entra app and Azure Bot IDs; set the secret again and run `netclaw doctor` |
| No reply in a channel | App not installed, ACL mismatch, or missing structured mention | Install the app, check canonical IDs, and mention the bot in a new root |
| Thread continuation does not work | Package was not upgraded with RSC | Increment the package version, upgrade it in that Team, and complete the consent prompt |
| Group Chat is silent | Ingress is off, chat ID is absent, or principal is unauthorized | Enable ingress, save the canonical chat ID, and add a global user or group grant |
| Friendly Group Chat search fails | `Chat.ReadBasic.All` is absent | Grant optional admin consent or enter the canonical chat ID manually |
| Group authorization fails | Graph consent or membership lookup failed | Grant `GroupMember.Read.All`; treat lookup failures as a deny and inspect non-secret diagnostics |
| A channel has only public tools | No audience override matched | Add an exact `ChannelAudienceOverrides` entry |
| Image is rejected | Attachments are disabled or validation failed | Enable `AllowAttachments`; use a supported image and do not bypass the trust gate |
| Package update is ignored | Version did not change | Increase the semantic package version before uploading or reinstalling |
| Secret appears in JSON | Secret is in the wrong store | Remove and rotate it, then use `netclaw secrets set Teams.ClientSecret` |

## Rotate or disable

Create a new Entra secret and store it with `netclaw secrets set Teams.ClientSecret '<new-secret>'`. Restart `netclawd`, run the checks above, then revoke the old secret. Keep the old secret active until the new one works.

Set `Teams.Enabled` to `false`, restart `netclawd`, and confirm the change with `netclaw status`. Then block or withdraw the Teams app. Revoke the secret only when the rollback is permanent.

## Related pages

- [Security model](/security/security-model/) - audiences and tool policy
- [`netclaw config`](/cli/config/) - the configuration dashboard
- [`netclaw secrets`](/cli/secrets/) - encrypted secret storage
- [Channel troubleshooting](/channels/troubleshooting/) - shared channel checks

## Resources

- [Microsoft Teams app manifest schema](https://learn.microsoft.com/en-us/microsoftteams/platform/resources/schema/manifest-schema)
- [Grant and manage Teams app permissions](https://learn.microsoft.com/en-us/microsoftteams/manage-consent-app-permissions)
- [Upload a custom Teams app](https://learn.microsoft.com/en-us/microsoftteams/platform/concepts/deploy-and-publish/apps-upload)
