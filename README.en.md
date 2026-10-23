# SMS Keeper

A native macOS app for managing the Messages database — built around **bulk cleanup** and **fast search**.

> 中文版：[README.md](README.md)

<p align="center">
  <img src="docs/images/dashboard.png" width="720" alt="Overview">
</p>

## Troubleshooting

Enable **Settings & Diagnostics › Diagnostics Log**, reproduce the issue, and send the
log file. It records steps and errors only — never message content, numbers or codes
(enforced in code). See [docs/troubleshooting.md](docs/troubleshooting.md).

## Why

The built-in Messages app on macOS has no bulk management: tens of thousands of
messages, one at a time, weak search, no way to clean up by category. Verification
codes, delivery notices and marketing texts pile up forever.

SMS Keeper reads `~/Library/Messages/chat.db` directly and turns it into searchable,
batch-processable data — **with an automatic backup before every delete, and a
trash that can restore the whole batch**.

## Features

### Automatic classification

Six categories, each with a human-readable reason (not a black box):

| Category | Example |
|---|---|
| Verification codes | "Your code is 630685, valid for 5 minutes" |
| Deliveries | "Pickup code 3-2-1024 at the locker" |
| Banking | "Card ending 8821 charged ¥128.50" |
| Promotions | "Flash sale — reply TD to unsubscribe" |
| Notifications | "Appointment on Oct 28, 9:00 AM" |
| Personal | "Dinner tonight?" |

### Bulk cleanup

12 built-in rules, always **preview the count and samples before running**:
duplicate codes, expired codes, read codes, all codes, old delivery notices,
all deliveries, promotions, low-value sweep, old bank notices, unread promotions,
empty messages, and bulk delete by age.

### Search

Multi-keyword AND, `"exact phrase"`, `-exclude`, `/regex/`, `sender:number`,
combined with category / time range / unread / attachments / sort.

### Export

Markdown, plain text or CSV, with a timestamped filename.
Export from the list, a multi-selection, or a single message.

### Safety

1. Quits Messages before writing to the database
2. Full database snapshot before every delete (last 20 kept)
3. Every deleted row archived to Trash — restorable, including rich-text payloads
4. Transactional delete with automatic rollback

## Requirements

- macOS **26.0+** (uses Liquid Glass)
- Command Line Tools to build (`xcode-select --install`) — full Xcode not required

## Getting started

```bash
git clone <repo-url>
cd sms-keeper

make build     # produces build/短信管家.app
make run       # build and launch
```

The app starts with **demo data** (630 sample messages) so you can try deleting
and restoring without touching real messages.

### Connecting real messages

1. Open the app → **Settings**
2. Click **Open System Settings** → **Privacy & Security › Full Disk Access**
3. Add `短信管家.app`
4. Quit and reopen the app, then click **Connect to Messages**

## Development

```bash
make selftest    # load / classify / search / navigation / delete-restore round trip
make snapshot    # regenerate screenshots in docs/images
make exporttest  # regenerate export samples in docs/examples
make clean
```

## Performance

10,000 messages on an M1 Pro: read ~150 ms, classify ~1.4 s (chunked, with progress),
filter ~20 ms, category switch 0–8 ms, search ~25 ms.

## Privacy

Everything runs locally. No network, no uploads. Only the copy is read; the original
database is written to only when you delete. Backups and trash live in
`~/Library/Application Support/SMSKeeper/`.

## License

[MIT](LICENSE)
