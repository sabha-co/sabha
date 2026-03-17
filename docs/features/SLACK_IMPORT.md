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
| User | User | Placeholder (no email, claimable later) |
| Public Channel | Rooms::Open | Auto-membership for listed members |
| Private Channel | Rooms::Closed | Explicit membership |
| DM | Rooms::Direct | 2+ participant matching |
| Thread (thread_ts) | Rooms::Thread | Linked to parent message |
| Reaction | Boost | Emoji name → Unicode mapping |
| `<@U123>` mention | `@username` | Plain text conversion |
| `<#C123\|name>` | `#name` | Channel reference |
| `<!channel>` | `@channel` | Broadcast mention |

## User Handling

Imported users are created as **placeholder accounts**:
- No email address (bypasses validation)
- No password (cannot log in)
- Marked with `slack_import: true` in preferences
- Stores `slack_user_id` and `slack_username` for future claiming

Users can later claim their imported account by:
1. Signing up with matching email
2. Admin manually linking accounts

## Message Conversion

### Mentions
```
<@U12345ABC>           → @username (first name)
<@U12345ABC|display>   → @username
<!channel>             → @channel
<!here>                → @here
<!everyone>            → @everyone
```

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
bin/rails test test/services/slack_importer_test.rb
```

Test fixtures are in `test/fixtures/slack_export/`:
- `users.json` - Sample users (active, deleted, bot)
- `channels.json` - Sample channels
- `general/2024-01-15.json` - Messages with mentions, reactions, threads
- `random/2024-01-15.json` - Messages with channel references

## Limitations

- **No file attachments**: Only message text is imported
- **No avatar images**: Users get default avatars
- **No private data without Business+**: Free/Pro exports only include public channels
- **No real-time sync**: One-time import only
- **Timestamp precision**: Preserved to the second (Slack uses microseconds)
