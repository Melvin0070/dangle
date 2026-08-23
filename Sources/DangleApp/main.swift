import AppKit
import DangleKit

// Before the delegate exists, because DangleEngine resolves the pack while it
// is being constructed as a stored property.
DanglePack.seedBundledPack()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
