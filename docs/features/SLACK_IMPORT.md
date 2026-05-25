# Slack Import Feature (Beta)

Import Slack workspace data into Sabha, enabling teams to migrate their chat history from Slack.

## Quick Start

1. **Export your Slack data**
   - Go to Slack → Settings & administration → Workspace settings → Import/Export Data
   - Click "Export" and wait for the download link

2. **Transfer the ZIP to your server**
   ```bash
   scp slack_export.zip user@your-server:/tmp/
   ```

3. **Validate the export** (optional but recommended)
   ```bash
   bin/rails slack:validate[/tmp/slack_export.zip]
   ```

4. **Run the import**
   ```bash
   bin/rails slack:import[/tmp/slack_export.zip]
   ```

   Set `SKIP_VALIDATION=1` to bypass the pre-import validation pass:
   ```bash
   SKIP_VALIDATION=1 bin/rails slack:import[/tmp/slack_export.zip]
   ```

Example output:
```
Validating Slack export: /tmp/slack_export.zip
✓ Valid export found
  Users: 25, Channels: 10

Starting import...

Found 25 users in export
Imported 23 users
Found 10 public channels
Created room: #General
Created room: #Random
...
Imported 5432 messages...
Processing 89 thread replies...
Created 45 threads

IMPORT_COMPLETE
IMPORT_STATS:{"users":23,"rooms":10,"messages":5432,"threads":45,"boosts":234}
```

## Validation

Before importing, you can validate the export file:

```bash
bin/rails slack:validate[/path/to/export.zip]
```

This checks:
- ZIP file is valid and readable
- Required files exist (`users.json`, `channels.json`)
- JSON files are parseable
- Reports counts of users, channels, private groups, and DMs

Example validation output:
```
Validating Slack export: /tmp/slack_export.zip

✓ Valid Slack export

Export contents:
  Users:            25
  Public channels:  10
  Private channels: 0
  Direct messages:  0
  Message files:    47

Warnings:
  ⚠ This export only contains public channels. Private channels and DMs require a Slack Business+ plan to export.

VALIDATION_PASSED
```

## Slack Export Format

Slack exports are ZIP files with this structure:

```
export.zip/
├── users.json           # User profiles
├── channels.json        # Public channels
├── groups.json          # Private channels (Business+ only)
├── dms.json             # Direct messages (Business+ only)
└── <channel-name>/      # Message folder per channel
    ├── 2024-01-01.json
    ├── 2024-01-02.json
    └── ...
```

**Export Limitations by Slack Plan:**
- Free/Pro: Public channels only
- Business+/Enterprise: Full export including private channels and DMs

## Data Mapping

| Slack Entity | Sabha Entity | Notes |
|--------------|-----------------|-------|
| User | User | Placeholder account (no email, no password) |
| Public Channel | Rooms::Open | All currently-active Sabha users are granted membership (not only the channel's listed members) |
| Private Channel | Rooms::Closed | Explicit membership for users named in the export |
| DM | Rooms::Direct | Matched to the original Slack participants via `Rooms::Direct.find_or_create_for` |
| Thread (`thread_ts`) | Rooms::Thread | Linked to parent message; all members of the parent room are added to the thread |
| Reaction | Boost | Emoji name → Unicode mapping |
| `<@U123>` mention | `@username` | Plain-text conversion (see below) |
| `<#C123\|name>` | `#name` | Channel reference |
| `<!channel>`, `<!here>`, `<!everyone>` | `@channel`, `@here`, `@everyone` | Broadcast mention |

If the import is run on a workspace with no administrator, the importer creates a synthetic "Slack Import" administrator user as the message author of record (see `Slack::ImportContext`). It is not deleted at the end of the run.

## User Handling

Imported users are created as **placeholder accounts**:
- No email address (bypasses validation via `validate: false`)
- No password — they cannot log in
- Marked with `slack_import: true` in preferences
- Store `slack_user_id` and `slack_username` for future correlation

**Bot users and deleted Slack users are skipped entirely** — their accounts are not created, and any messages they authored are dropped with a warning at import time.

There is currently no built-in flow for the original Slack user to claim their imported account. Admins who want to associate a real user with imported history can update the placeholder user's `email_address` and `password` via the console or admin UI; that's it. (A signup-time matcher and an admin-side claim flow are not implemented.)

## Message Conversion

### Mentions
```
<@U12345ABC>           → @firstname  (lowercased first name from the user's Slack profile)
<@U12345ABC|display>   → @firstname  (the |display segment is ignored)
<@UNKNOWN>             → @unknown    (if the user ID isn't in users.json)
<!channel>             → @channel
<!here>                → @here
<!everyone>            → @everyone
```

Mentions resolve through the user map built from `users.json` and always use the lowercased first name — display-name overrides are not honored.

### Links
```
<https://example.com>              → https://example.com
<https://example.com|Example>      → Example (https://example.com)
```

### Channel References
```
<#C12345ABC|general>   → #general
```

### Skipped Message Types
- `channel_join` - User joined channel
- `channel_leave` - User left channel
- `channel_purpose` - Purpose was set
- `channel_topic` - Topic was changed

## Emoji Mapping

Common Slack emoji names are mapped to Unicode:

| Slack | Unicode |
|-------|---------|
| thumbsup, +1 | 👍 |
| heart | ❤️ |
| fire | 🔥 |
| tada | 🎉 |
| rocket | 🚀 |
| eyes | 👀 |
| 100 | 💯 |

Unknown emoji default to 👍.

## Idempotency

The importer is **idempotent** - running the same import multiple times is safe:

- **Users**: Matched by `slack_user_id` in preferences, skipped if exists
- **Rooms**: Matched by name (case-insensitive), skipped if exists
- **Messages**: Matched by `client_message_id` (Slack's `ts`), skipped if exists
- **Boosts**: Matched by user + message + content combination, skipped if exists
- **Threads**: Created only if parent message has replies and thread doesn't exist

This allows retrying failed imports or re-importing to pick up any missed data.

## Error Handling

| Scenario | Handling |
|----------|----------|
| Invalid ZIP format | Validation fails with error message |
| Missing users.json/channels.json | Validation fails |
| Malformed JSON | Skip entry, log warning, continue |
| Duplicate room names | Reuse existing room (case-insensitive match) |

All imports are wrapped in a database transaction - if any step fails, all changes are rolled back.

## Testing

Run the test suite:

```bash
bin/rails test test/lib/slack/importer_test.rb
```

Test fixtures are in `test/fixtures/slack_export/`:
- `users.json` - Sample users (active, deleted, bot)
- `channels.json` - Sample channels
- `general/2024-01-15.json` - Messages with mentions, reactions, threads
- `random/2024-01-15.json` - Messages with channel references

## Limitations

- **No file attachments** — only message text is imported.
- **No avatar images** — users get default avatars.
- **No private data without Business+** — Free/Pro exports only include public channels.
- **No real-time sync** — one-time import only.
- **Timestamp precision** — preserved to the second (Slack uses microseconds).
- **Bot and deleted users are skipped** — neither the user nor their messages are imported.
- **Empty post-conversion bodies are dropped silently** — if a Slack message converts to a blank string after mention/link normalization, the message is not created.
- **Public-channel membership is everyone-wide** — every active Sabha user is added to each imported public channel, not just the users listed as members in the export.
- **No claim flow** — placeholder users cannot self-claim; admins must edit the placeholder's email/password manually.
