# What’s New comics

Bilingual comic companions for DDock release notes. The native Update window renders a comic when the GitHub Release includes one. Releases without a comic keep the notes-only window.

- Authoring spec: [COMIC-TEMPLATE.md](COMIC-TEMPLATE.md)
- Sparkle notes: `<MARKETING_VERSION>.md` (German first, then `## English`)
- Comic copy: `<MARKETING_VERSION>-comic.md`
- Optional review preview: `<MARKETING_VERSION>-comic.html`
- Panel art: `assets/<MARKETING_VERSION>/panel-0N.png`
- HTML starter with Google Fonts: [comic-preview.template.html](comic-preview.template.html)

## GitHub Release assets

Esi attaches these files to the draft next to `DDock.md`. The Release workflow does not upload them yet.

| File on the release | Source in the repo |
| --- | --- |
| `DDock-comic.md` | `docs/releases/<MARKETING_VERSION>-comic.md` |
| `panel-01.png` … `panel-04.png` | `docs/releases/assets/<MARKETING_VERSION>/panel-0N.png` |

The Update window requests `DDock-comic.md` from the same directory as Sparkle’s `releaseNotesURL`, or from the enclosure ZIP directory when that notes URL is missing. Relative image paths in the markdown resolve against that directory. A same-directory `panel-0N.png` fallback covers the flat GitHub Release layout.

## Security

The in-app window parses the markdown itself. It does not load remote CSS, scripts, Google Fonts, or arbitrary embedded media. Panel images use HTTPS only, and only for `benjamin-kraatz/DeeDock` on GitHub Releases or `raw.githubusercontent.com`. Local `file` or `Data` paths are for previews and tests. A failed image fetch leaves a placeholder and keeps the text.

Google Fonts belong only in static `*-comic.html` review files. See the template.

Esi reviews tone and format. Nara does not cut releases.
