# What’s New comics

Bilingual comic companions for DDock release notes. The native Update window can render a comic when the GitHub Release includes one. Releases without a comic keep the notes-only window.

The renderer is a platform capability. It does not ship a version-specific comic package. Do not add `0.4.1-comic.md` or `assets/0.4.1/` on the renderer branch. The first authored comic is 0.5.0: Focus, Compost, and Gossip.

- Authoring spec: [COMIC-TEMPLATE.md](COMIC-TEMPLATE.md)
- Sparkle notes: `<MARKETING_VERSION>.md` (German first, then `## English`)
- Comic copy: `<MARKETING_VERSION>-comic.md`
- Optional review preview: `<MARKETING_VERSION>-comic.html`
- Panel art: `assets/<MARKETING_VERSION>/panel-0N.png`
- HTML starter with Google Fonts: [comic-preview.template.html](comic-preview.template.html)

Current authored comic: [0.5.0-comic.md](0.5.0-comic.md) and [0.5.0-comic.html](0.5.0-comic.html), with notes in [0.5.0.md](0.5.0.md).

## GitHub Release assets

When `docs/releases/<MARKETING_VERSION>-comic.md` is on the shipped commit, the Release workflow copies it to staging as `DDock-comic.md` and copies each `docs/releases/assets/<MARKETING_VERSION>/panel-0N.png` beside it as a flat `panel-0N.png`. Those files go into the Sparkle artifact upload and onto the draft GitHub Release next to `DDock.zip`, `appcast.xml`, and `DDock.md`. The staged markdown rewrites `assets/<ver>/panel-0N.png` links to `panel-0N.png` so the Update window can load art from the same directory. If that comic file is missing, the ship stays notes-only and does not fail.

| File on the release | Source in the repo |
| --- | --- |
| `DDock-comic.md` | `docs/releases/<MARKETING_VERSION>-comic.md` |
| `panel-01.png` … `panel-0N.png` | `docs/releases/assets/<MARKETING_VERSION>/panel-0N.png` |

The Update window requests `DDock-comic.md` from the same directory as Sparkle’s `releaseNotesURL`, or from the enclosure ZIP directory when that notes URL is missing. Relative image paths in the markdown resolve against that directory. A same-directory `panel-0N.png` fallback still covers a comic that kept the authored `assets/<ver>/` path.

## Security

The in-app window parses the markdown itself. It does not load remote CSS, scripts, Google Fonts, or arbitrary embedded media. Panel images use HTTPS only, and only for `benjamin-kraatz/DeeDock` on GitHub Releases or `raw.githubusercontent.com`. Local `file` or `Data` paths are for previews and tests. A failed image fetch leaves a placeholder and keeps the text.

Google Fonts belong only in static `*-comic.html` review files. See the template.

Esi reviews tone and format. Nara does not cut releases.
