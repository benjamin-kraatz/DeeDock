# App Fusion

App Fusion turns two deliberately selected window contexts into an editable comparison,
difference summary, or checklist. It uses the on-device Apple Intelligence model. It does
not modify source applications, send messages, or read complete documents.

## Create an artifact

1. Choose **Add to Fusion** on a Window Peek card. In keyboard Peek, press **F** for the selected card.
2. Add another window from Peek, or use **Choose or refresh windows** in the tray. You can also open **App Fusion** from the DDock menu-bar item to start with the picker.
3. Check the two source cards. Use **Remove** or **Replace** to correct the selection.
4. Choose **Capture selected windows**. Screen Recording permission must already be enabled through Settings.
5. Review the recognized text. Correct OCR errors or supply your own notes, then choose an action and optionally add an instruction.
6. Confirm that you reviewed the available input and its limitations. Choose **Generate with Apple Intelligence**.
7. Edit the result, then choose **Save to Shelf**. The saved UTF-8 text file opens with its default native application.

Compare and Summarize differences require nonempty reviewed text for both sources. Create
checklist can use one source when the other is unreadable. Supplied or edited text is marked
in the artifact's provenance. An empty source cannot support a generated point's citation.

The tray stays open while you navigate other apps, dock previews, displays, and Spaces.
**Hide tray**, Escape, and the window close button release captured input but preserve the
selection and any generated draft. **Cancel attempt** retains already reviewed input for an
intentional retry. **Discard and start over** cancels work and clears the selection and draft.
These controls do not remove an artifact already saved to Shelf.

## Content and lifetime

Capture uses the existing ScreenCaptureKit and Vision service. It processes selected windows
serially with a 1,200 by 900 pixel bounding box. The Fusion flow re-discovers windows before
capture and matches window ID, process, bundle identity, and title. The shared capture service
also checks the process and title immediately before capture. A closed or changed source is
reported as unavailable. Ambiguous Peek matches require an explicit picker selection.

Only reviewed text enters the model. Images, layout, hidden content, and other document pages
are excluded. OCR is limited to 6,000 characters per source; shortened captures are marked.
The instruction is limited to 500 characters. Input review shows exactly the text supplied to
the model. Editing the text clears the review confirmation.

Images remain in the capture operation and are released when it finishes. Fusion writes no
temporary screenshot files. Reviewed input remains in memory for at most fifteen minutes
while idle, with a wall-clock expiry check before generation and when the app becomes active.
Hide, discard, sleep, display sleep, session lock, and successful generation clear the reviewed
input. Cancellation requests cannot force an Apple API to release its in-flight buffers before
that API returns.

Discovery, capture, and generation have a 90-second deadline. Late results are rejected.
Replacement work waits for the previous cancelled attempt to finish, preventing overlapping
captures or model requests. Saving completes its file/reference transaction without a cancel
control. The result draft remains available when a save fails.

## Model and validation

`FoundationModelsFusionComposer` creates a fresh `LanguageModelSession` for each attempt.
It uses `SystemLanguageModel.default`, requires guided generation, and supplies no tools.
The instructions treat source text and titles as untrusted data. The typed response contains
a title, a summary, and up to eight points with source numbers. Validation rejects empty or
oversized content, invalid or duplicate source numbers, and references to empty sources.
Provenance comes from the reviewed input snapshot, never from generated metadata.

The installed macOS 27 SDK exposes image attachments and the `.vision` capability. Fusion
intentionally uses the text path so every input is reviewable. The code counts prompt,
instruction, and generated-schema tokens against the model's actual `contextSize`, reserving
700 response tokens and 200 tokens for framing. It refuses an oversized input rather than
silently shortening text after review. Model refusal, unavailability, context limits, invalid
output, capture failures, and timeout produce errors without fabricated fallback results.

API references: [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel),
[contextSize](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/contextsize), and
[Foundation Models updates](https://developer.apple.com/documentation/Updates/FoundationModels).
The local SDK declarations, rather than older text-only documentation, determine compilation.

## Shelf storage

Shelf stores security-scoped file references in its existing `dock.shelf.v1` document.
`FusionArtifactStore` writes a UUID-named text file under the app's Application Support
`<bundle identifier>/Fusion` directory, then `FusionState` adds its URL through
`ShelfController.add`. A rejected reference rolls back the newly written file. If rollback
also fails, the error includes the retained file's recovery location. The draft remains editable.

The file contains the edited result, operation, generation time, fixed limitations, application
names, bundle identifiers, window titles, capture attempt times, capture states, and input-edit
markers. Raw OCR, screenshots, and the instruction are not separately persisted. The approved
result can quote or summarize source content. After saving, the tray disables its draft editors;
**Open saved file** allows subsequent editing in the file's native application.

Removing a Shelf item removes its reference and keeps its file. Shelf retains its existing
UserDefaults persistence behavior. There is no cross-store crash transaction: a process crash
between the file write and Shelf insertion can leave an unreferenced file in the Fusion folder.
Successful save/restart acceptance still requires a hands-on check.

## State cases worth testing

No tests are executed as part of this issue without explicit authorization. Useful future cases are:

- Select two windows of one app and two different apps; reject duplicate IDs, ambiguous Peek matches, and a third source without replacement.
- Replace or remove either source; invalidate capture and review without changing ordinary dock navigation.
- Reject changed identities before capture; report unreadable and missing sources without pretending to read their content.
- Bound text and instructions; require both sources for comparison and at least one for a checklist; clear confirmation after editing.
- Reject late capture and generation results after cancel, hide, reset, expiry, or a newer attempt; serialize replacement work.
- Reject unknown, duplicate, or empty-source citations and oversized/empty generated fields.
- Preserve reviewed input after model failure and cancellation; expire it on the wall-clock deadline and clear it after generation.
- Preserve the draft on a full/corrupt Shelf, file-write failure, bookmark failure, or reference-save failure; roll back only the newly created file.
- Preserve frozen provenance while editing the draft; prevent repeated Save from creating duplicate files.

See [the manual acceptance checklist](ACCEPTANCE.md#app-fusion-dee-16) for runtime work.
