# Sensitive window previews

Window Peek, Radar, and Hub Windows show the app icon until they have classified the captured frame. DOKK covers a sensitive result. Click **Show preview** or select the window and press **Option-R**. Click the crossed-out eye or press **Option-R** again to cover it. The reveal expires on a window switch, refresh, or close. A missing capture or failed classification shows the app icon and **Preview unavailable**.

Window Peek uses session-scoped window tokens. It joins Accessibility and ScreenCaptureKit windows by process, title, and frame, and uses ScreenCaptureKit metadata when Accessibility is unavailable. Cards request one-shot captures as they enter view. A window action can replace a card and request another capture. Radar and Hub Windows use window-server numbers tied to their discovery session. Radar captures while opening. Hub Windows discards previous frames when it rediscovers windows.

A covered card can enlarge on hover. The larger cover explains why DOKK hid the preview and offers the same reveal control as the card. Revealing the enlarged preview displays the card's captured frame. For cleared thumbnails, enlarged Peek can request a sharper frame and classifies it independently. Split Peek and opt-in Peek history use cleared frames. Explicit capture tools such as Mark up window still take their own capture when invoked. The privacy classifier keeps frames and recognized text in memory and sends neither to logging or analytics. Window titles still appear.

## Dataset and threshold

All 1,848 images came from fictional windows. Each family varies the window dimensions, thumbnail budget, appearance, and layout. Every family contains three sensitive categories and four ordinary categories, with 24 images per category. The ordinary set includes login documentation, six-digit reference numbers, public chat, and general application windows.

| Split | Layout families | Images |
| --- | --- | ---: |
| Training | Browser, workspace, editor, dashboard, mail, preferences | 1,008 |
| Validation | Portal, inspector | 336 |
| Final test | Library, metrics, review | 504 |

The generator fits each window into a capture budget from 160 × 100 to 800 × 500 pixels, preserving aspect ratio. These cover the standard Peek sizes at 1× and 2× plus a larger preview. Radar and Hub budgets vary with their layout and display scale.

Create ML trained a logistic classifier on ScenePrint features. The image-only model missed many code and private chat windows during development. The bundled pipeline runs Vision OCR when the image score falls below the threshold. It scales the input for text detection and looks for a small set of English sign-in, code, and private-chat phrases. Upscaling helps Vision detect small glyphs when capture retains enough detail. [Create ML image classifier](https://developer.apple.com/documentation/createml/mlimageclassifier/init%28trainingdata%3Aparameters%3A%29-7j4w6), [Core ML image classification with Vision](https://developer.apple.com/documentation/coreml/classifying-images-with-vision-and-core-ml).

The validation sweep charged five points per missed sensitive frame and one point per ordinary frame hidden. Thresholds 0.40 and 0.60 tied at 108 points. The selected threshold is 0.40, the more cautious of the two. The final-test families were generated after the policy was selected.

## Synthetic-only results

The evaluator ran on a Mac16,3 with Xcode 27.2 and macOS 27.2.1. It calls the app's own scoring code. Timings cover inference on decoded frames and exclude capture, model loading, and queue time.

| Final-test category | Image only | Image and OCR |
| --- | ---: | ---: |
| Sign-in dialogs missed | 0 / 72 | 0 / 72 |
| One-time codes missed | 31 / 72 | 6 / 72 |
| Private chats missed | 22 / 72 | 4 / 72 |
| Login documentation hidden | 14 / 72 | 14 / 72 |
| Ordinary six-digit numbers hidden | 40 / 72 | 40 / 72 |
| Public chats hidden | 46 / 72 | 46 / 72 |
| General app windows hidden | 8 / 72 | 8 / 72 |
| Inference p50 | 5.10 ms | 9.14 ms |
| Inference p95 | 9.52 ms | 108.13 ms |

The bundled pipeline missed 10 of 216 sensitive frames and hid 108 of 288 ordinary frames. The first accurate OCR call in the app test host took about 26 seconds. Later calls can use the initialized system OCR assets. The icon remains visible while the call is pending.

The results describe this generator. Its layouts share a rendering engine, common widgets, and a small English vocabulary. Small text, other languages, and real application layouts still need evaluation. ScreenCaptureKit excludes child windows in this capture path, so a separate child window may be absent from the frame. DOKK checks each capture as it arrives.

## Reproduce training and evaluation

Run these commands from the repository root on macOS 27 with Xcode 27 and Python 3. The scripts create PNGs and a model outside the repository. To replace the app model, copy the resulting `SensitiveWindowPreview.mlmodel` into `DeeDock/Resources`.

```sh
work="$(mktemp -d)"
python3 -m venv "$work/venv"
"$work/venv/bin/pip" install Pillow==13.0.0
"$work/venv/bin/python" scripts/preview-privacy/generate.py "$work/dataset"

xcrun swiftc -parse-as-library scripts/preview-privacy/Train.swift -o "$work/train"
"$work/train" "$work/dataset" "$work/SensitiveWindowPreview.mlmodel"

xcrun swiftc -O -parse-as-library \
    DeeDock/Dock/Peek/Privacy/WindowPreviewScoring.swift \
    scripts/preview-privacy/Evaluate.swift -o "$work/evaluate"
"$work/evaluate" "$work/dataset" "$work/SensitiveWindowPreview.mlmodel"
```

Xcode compiles the bundled model to `SensitiveWindowPreview.mlmodelc`. The checked-in model is 16,896 bytes. SHA-256 is `697d09d79db5a92d179bd131f665fd4197b215a7a6149fb612d9ee19738328ff`. Training output can vary with the Create ML version.

## macOS verification

The Debug build and 52 targeted tests passed. The tests cover a clear preview, a hidden preview, reveal and reset, missing and invalid models, a safe-to-sensitive replacement, stale results, and the bundled model. They also exercise the existing Peek, Radar, and Hub Windows suites.

The unsigned Xcode test host lacked Screen Recording access. A separately authorized local process captured two synthetic windows at 640 × 400 through DOKK's ScreenCaptureKit capture code. The live test fed those frames to the normal keyboard Peek entry point on a test dock. The classifier cleared the ordinary window and hid the sign-in window. The native panel processed Option-R, showed the hidden frame, hid it on window switch, and cleared its state on close. The live test used injected discovery and capture results inside the test host. It did not validate capture permissions in the built app, the physical mouse interaction, VoiceOver, or live Radar and Hub Windows.
