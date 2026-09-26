# Window Peek markup

Markup turns a Window Peek card into an annotated screenshot without leaving the dock. Choose
**Mark up window…** from a card's context menu, its revealed pencil button, or VoiceOver actions.
In keyboard Peek, select a card and press **M**. With the enlarged preview on, resting the pointer
on the staged picture shows a small toolbar with **Mark up**, Copy, and Save; see
[holding the enlarged preview](#holding-the-enlarged-preview).

Opening a markup closes Peek and opens one floating editor window. If a markup with marks on it is
already open, it comes forward and says so rather than being replaced.

## The picture

The editor starts with the Peek thumbnail, or the enlarged preview's sharper capture, and requests
one new ScreenCaptureKit capture of the window at its full backing resolution. The header says
which it is showing. Marks are stored in that full-resolution space, so a line drawn over the quick
preview lands on the same pixels once the sharp capture arrives. Minimized windows keep the
preview; **Recapture** takes a new picture at any time and keeps the marks.

## Tools

The palette on the left holds Select, Pen, Highlighter, Arrow, Rectangle, Text, Number badge,
Redact, and Crop. Each has a single-letter key: V, P, H, A, R, T, B, X, C. Colours are the number
keys 1 to 8; `[` and `]` step the weight. Colour and weight are captured when a mark is made; with
a mark selected, changing either restyles that mark.

- **Pen** and **Highlighter** are freehand. The highlighter multiplies, so text stays readable.
- **Arrow** and **Rectangle** go from the drag's start to its end.
- **Text** places a label at the click and starts typing. Return finishes, Option-Return adds a
  line, and an empty label disappears. Click a selected text mark again, or press Return, to edit.
- **Number badge** places the next number at each click.
- **Redact** pixelates or blacks out a rectangle. Pixelation is computed once for the whole picture
  and clipped per redaction. The export contains the redacted pixels, never the originals.
- **Crop** draws the export selection. Drag the corners or the inside to adjust; **Whole picture**
  removes it. The crop also limits Copy Text and Search Web.
- **Select** moves any mark. Delete removes the selected mark. One drag is one undo step.

⌘Z and ⇧⌘Z undo and redo. **Clear** removes every mark.

## Leaving the editor

- **Copy** (⌘C) puts the finished picture on the clipboard as PNG and TIFF. With Live Text on and
  text selected, ⌘C copies that text instead.
- **Save…** (⌘S) opens the save panel in the markup folder. The format is a setting.
- **Share** opens the system share picker.
- **Send to Shelf** writes the picture into the markup folder and stages that file on the Shelf.
  This is the one action that writes without a panel. It is hidden while the Shelf tile is off.
- **Drag** hands the picture to another app or, as a file, to Finder.
- **Live Text** overlays VisionKit's text selection, data detectors, and Visual Look Up.
- **Copy Text** (⇧⌘C) copies the Live Text selection, or the recognised text of the crop or picture.
- **Search Web** opens the configured engine with the selection or the first recognised lines.
  Pixels never leave the Mac: there is no public API for a browser's reverse image search, and
  uploading the capture to a third party is not something DeeDock does.
- **Frame** wraps the export in a mat coloured from the app icon, with rounded corners.

Escape finishes typing, leaves Live Text, clears the selection, drops the crop, and finally closes
the window. With marks on the picture a first Escape only warns; a second within 2.5 seconds
discards them.

## Settings

**Settings → Features → Window Peek → Markup** holds the saved file format (PNG or JPEG), the search
engine for Search Web (Google, DuckDuckGo, Bing, Ecosia), and the markup folder. The folder defaults
to `~/Pictures/DeeDock Markups`. It is created on first use by Send to Shelf.

## Holding the enlarged preview

The stage used to dismiss 120 ms after the pointer left a card, so the picture could not be reached.
Now `WindowPeekEnlargeHold` decides from the pointer's position: on the hero block the stage is held
and shows its toolbar; inside the corridor between the Peek panel and the hero (their bounding box)
it waits up to 650 ms for the pointer to arrive; anywhere else it dismisses as before, so moving
away still closes Peek. While held or waiting, the pointer counts as being on the Peek panel. The
toolbar is its own small mouse-accepting panel, since the stage stays click-through for the cards;
Peek's outside-click monitor treats it as Peek's own window.

## Privacy

Markup writes to disk only on Save…, Send to Shelf, or a Finder drop that asks for a file. Copy and
Share stay in memory and the pasteboard. Vision text recognition and pixelation run on the device.
Live Text's Visual Look Up is Apple's feature and follows Apple's own policy when the user invokes
it.

## Accessibility

Every control is labelled, and tool selection, colour, weight, copy, save, crop reset, and text
extraction work from the keyboard. Freehand drawing needs a pointer; the canvas says so in its
hint. Reduce Motion replaces the picture's flight from the enlarged preview and the chrome's
settle with fades. Reduce Transparency makes the window and its floating controls opaque.

## Pending native acceptance

Compilation is checked. Not yet exercised by hand: the flight from a staged hero into the editor,
drawing feel at high pointer rates, the Live Text overlay's selection and Visual Look Up on a
captured window, Finder drops from the drag handle, the share picker's anchor, the save sheet on a
non-activating panel, Send to Shelf with the Shelf open, the hero toolbar's clicks with Peek's
monitors, and Reduce Motion and Reduce Transparency.
