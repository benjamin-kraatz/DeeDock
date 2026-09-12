# What’s New comic template

Authoring spec for bilingual What’s New comics. The native Update window renders this markdown when the GitHub Release includes `DDock-comic.md` and the panel PNGs. Esi reviews tone before a release ships. Nara does not cut releases.

A release comic lives next to its notes:

- Notes: `docs/releases/<MARKETING_VERSION>.md`
- Comic: `docs/releases/<MARKETING_VERSION>-comic.md`
- Optional preview: `docs/releases/<MARKETING_VERSION>-comic.html`
- Art: `docs/releases/assets/<MARKETING_VERSION>/panel-0N.png`

See [COMIC-README.md](COMIC-README.md) for the file map and the GitHub Release names.

## Count

Default is 3 panels. 2 is a small release. 4 is the maximum. Pick the features that photograph, not a tour of every bullet.

## Copy limits, per language

Count words in that language. Keep both German and English inside the same cap.

| Field | Max words |
| --- | --- |
| Title | 6 |
| Speech | 8 |
| Caption | 32 |

Speech is the spoken line shown next to the art, not a second caption. Leave speech empty when the panel has no voice.

## Art

Shared across German and English. One PNG per panel, about 3:2 landscape.

- Cream paper ground
- Indigo outlines
- Lilac, mint, and coral
- Smiling utility objects, not branded app icons
- No letters in the drawing. Title, speech, caption, and alt live outside the PNG so they stay selectable.

Name files `panel-01.png`, `panel-02.png`, and so on.

## Layout

German first, then English.

1. Write every panel in German: art, title, speech, caption, German alt.
2. Add `## English`.
3. Repeat the panels in English: same art path, English title, speech, caption, and English alt.

Keep selectable text in the markdown, the HTML preview, and the Update window. Do not bake German or English into the PNG.

## Alt text

Each panel needs German alt and English alt. Put the German alt on the image in the German block. Put the English alt on the image in the English block. One sentence. Name what a screen reader should know.

## Markdown shape

```markdown
# DDock <version> What’s New

Comic for the [release notes](<version>.md).

## Panel 01 — <short German topic>

![<German alt>](assets/<version>/panel-01.png)

**<German title>**

> <German speech>

<German caption>

## English

### Panel 01 — <short English topic>

![<English alt>](assets/<version>/panel-01.png)

**<English title>**

> <English speech>

<English caption>
```

Repeat the panel headings for 02 and 03 (or 02 only, or through 04). Link the full notes from the comic. Link the comic from the notes only when that helps Esi review.

## Native Update window

DDock fetches `DDock-comic.md` from the same directory as Sparkle’s notes URL (or the enclosure ZIP). It parses this markdown on a native path. Wide windows show art, then German and English columns. Narrow windows stack art, then German, then English. Text is selectable. Reduce Motion adds no extra motion because the view does not animate. A missing or rejected image shows a placeholder and keeps the copy. Releases without a comic keep today’s notes-only window.

Do not put remote stylesheets, scripts, or Google Fonts in the markdown. The app will not load them.

## Preview HTML

Optional. Copy [comic-preview.template.html](comic-preview.template.html) to `*-comic.html` for review: art on top, German column, English column. No app chrome.

That static file may load one Google Fonts family. Use Source Serif 4. Do not load a pile of families. Put this in the preview `<head>` only:

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Source+Serif+4:opsz,wght@8..60,400;8..60,600&display=swap" rel="stylesheet">
```

The Update window never uses that `<link>`. Do not add Google Fonts to Sparkle notes, `DDock-comic.md`, or any in-app HTML.

## GitHub Release names

When `docs/releases/<MARKETING_VERSION>-comic.md` exists on the shipped commit, the Release workflow uploads these next to `DDock.md`:

- `DDock-comic.md` from `docs/releases/<MARKETING_VERSION>-comic.md`
- `panel-0N.png` from `docs/releases/assets/<MARKETING_VERSION>/panel-0N.png`

A missing comic file is skipped. The notes-only ship still succeeds. Do not add `0.4.1-comic.md` or `assets/0.4.1/`. A 0.5.0 Focus, Compost, and Gossip comic belongs only to 0.5.0.

## Process

Land the native renderer first, with no version-specific comic content. Author the first real comic in the same 0.5.0 release-prep PR as the version bump and `docs/releases/0.5.0.md`. Do not dispatch Release from that PR. Esi merges, then ships. The workflow attaches comic assets on the draft when that cut has one.
