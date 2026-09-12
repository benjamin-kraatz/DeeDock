# Peek history

Peek history makes text from past Window Peeks searchable on this Mac. Collection starts off.

## Use the history

1. Open **Settings → Features → Window Peek**.
2. Read the privacy disclosure and enable **Save text from peeks**.
3. Allow Screen Recording under **Features → Permissions** if needed.
4. Open Window Peek on a running app with readable window content.
5. Choose **Search peek history…** in the Window Peek settings.

Search matches recognized text, app names, and window titles. Every query word must match.
Matching ignores case and diacritics through the system's localized search comparison.
An empty query shows recent entries, newest first. Each result includes its capture time and
selectable recognized text. Results describe past content and do not activate a live window.

Use **Delete entry** to remove one record or **Clear history** to remove the entire index.
Clear history asks for confirmation. Turning collection off cancels unfinished recognition
and retains saved entries. Clear does not turn collection off, so future peeks can be saved again.
An atomic save already submitted when collection is paused may finish. Deletion waits for
that save before removing data, and rejects older capture batches that finish afterward.

## Privacy and storage

Apple Vision recognizes text locally. DDock saves recognized text, app names, window titles,
and capture timestamps. It does not save images, upload history, or send text to a language model.
The feature adds no network client or system Dock preference changes.

Text can contain private messages, passwords, and other sensitive content. There is no automatic
redaction in v0. Screen Recording access and history collection are separate controls. The
history toggle never requests a system permission by itself.

The plaintext index lives at `~/Library/Application Support/DDock/PeekHistory/index.json`
in the current unsandboxed app. The directory is marked as excluded from backups. The directory
and file use owner-only permissions. Other software acting as the same user can still read or
copy the file. DDock cannot remove copies made by external software.

Search covers seven days with at most 500 records. Expired records are removed from disk on
app launch or the next successful OCR batch. Individual deletion also prunes expired records.
An idle app can retain expired bytes until one of those events. Clear removes the index file.
Unreadable storage stops collection and requires explicit clearing before collection can resume.

## Capture limits

OCR uses thumbnails accepted by the visible Peek presentation. With collection enabled, the same
one-shot capture contains up to 1600 × 1000 pixels for recognition. Its displayed size is unchanged.
It does not capture
additional windows or run a background screen recorder. The capture epoch prevents a batch
started before opt-in, pause, or deletion from entering a later history session.

At most eight cards enter one OCR batch. New batches are skipped while recognition or a storage
control is busy. Identical app, title, and text records are deduplicated. A new text creates a new
record. Each record contains at most 8,000 recognized characters. Vision processing and disk I/O
run on separate actors outside the main actor.

Thumbnail resolution, small fonts, unsupported scripts, protected content, and capture failures
can reduce OCR accuracy. Empty OCR produces no record. History is not a complete record of all
windows, all visible text, or every Peek. Apple Intelligence availability is not required.
