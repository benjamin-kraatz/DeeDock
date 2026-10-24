// Throwaway target app: one titled window with a text view. Used only as something safe to move/edit.
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let env = ProcessInfo.processInfo.environment
let w = NSWindow(contentRect: NSRect(x: 520, y: 380, width: 760, height: 420), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
if env["TARGET_LIGHT"] != nil { w.appearance = NSAppearance(named: .aqua) }
w.title = "Companion Lab Target"
let tv = NSTextView(frame: w.contentView!.bounds); tv.autoresizingMask = [.width, .height]
tv.string = "The quick brown fox jumps over the lazy dog. Selected text should be replaceable via AX."
w.contentView!.addSubview(tv)
w.orderFrontRegardless()
print("WID \(w.windowNumber)"); fflush(stdout)
app.run()
