import AppKit
import ImageIO

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory); app.finishLaunching()
    let resources = URL(fileURLWithPath: "Sources/AmplifierApp/Resources", isDirectory: true)
    var renderCount = 0
    let destination = ProcessInfo.processInfo.environment["AVATAR_CHECK_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    if let destination { try! FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true) }
    let window = NSPanel(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 320),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isOpaque = false; window.backgroundColor = .clear
    let sprite = SpriteView(frame: NSRect(x: 0, y: 0, width: 320, height: 320)); window.contentView = sprite
    window.orderFrontRegardless()
    @MainActor func render() -> NSBitmapImageRep {
        // Draw the current frame into an explicit AppKit bitmap context. An
        // offscreen window's cached display can remain unchanged on CI hosts.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 320,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 1280, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current!.cgContext.clear(sprite.bounds)
        sprite.draw(sprite.bounds)
        NSGraphicsContext.restoreGraphicsState()
        precondition((0..<320).contains { y in (0..<320).contains { x in bitmap.colorAt(x: x, y: y)!.alphaComponent > 0 } }, "Rendered artwork must not be blank")
        return bitmap
    }
    for finish in ["clear", "dark"] {
        for shape in AvatarCatalog.shapes {
            let resource = AvatarAppearance.resourceName(shape, finish: finish)
            let poses = NSImage(contentsOf: resources.appendingPathComponent(resource + ".png"))!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            precondition(poses.width == 1280 && poses.height == 320*((AvatarCatalog.frameCount(shape)+3)/4))
            let thumbnail = AvatarAppearance.thumbnail(poses, palette: "blue", shape: shape)
            precondition(thumbnail.size.width == 78)
            sprite.load(shape, finish: finish, directory: resources)
            if !["relay", "meter"].contains(shape) {
                let url = resources.appendingPathComponent(resource + "-working.png")
                let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)!
                let count = CGImageSourceGetCount(source); precondition(count > 100)
                let started = ProcessInfo.processInfo.systemUptime
                for i in 0..<count {
                    let frame = CGImageSourceCreateImageAtIndex(source, i, [kCGImageSourceShouldCache: false] as CFDictionary)!
                    precondition(frame.width == 256 && frame.height == 256 && frame.alphaInfo != .none)
                    let context = CGContext(data: nil, width: 192, height: 192, bitsPerComponent: 8, bytesPerRow: 768,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    context.draw(frame, in: CGRect(x: 0, y: 0, width: 192, height: 192))
                }
                let milliseconds = (ProcessInfo.processInfo.systemUptime-started)*1000/Double(count)
                print("DECODE \(resource): \(count) frames, \(String(format: "%.2f", milliseconds)) ms/frame")
            }
            for state in AvatarState.allCases {
                let kind = state == .error ? "session-error" : (state == .review ? "approval" : "completion")
                let attention = [AvatarState.error,.review,.ready].contains(state) ? [AttentionItem(id: "sample", fingerprint: state.rawValue, sessionId: "sample", title: "Sample", kind: kind, summary: "Sample", pinned: false, agentCreated: false)] : []
                sprite.update(connected: ![.offline,.connecting].contains(state), connecting: state == .connecting,
                              working: state == .working ? 1 : 0, items: attention, scope: resource)
                precondition(sprite.playback.state == state)
                sprite.previewElapsed = 0.65
                let bitmap = render()
                // Transparent corners must survive native composition.
                precondition(bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0)
                precondition(sprite.visibleArtworkBounds.width > 40)
                if let destination {
                    try! bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(resource + "-" + state.rawValue + ".png"))
                }
                renderCount += 1
            }
            // Real renderer must select the working atlas/APNG after a reaction,
            // even though the host still reports unread attention.
            for kind in ["completion", "session-error"] {
                sprite.update(connected: true, connecting: false, working: 2,
                    items: [AttentionItem(id: "mixed", fingerprint: kind, sessionId: "sample", title: "Sample", kind: kind, summary: "Sample", pinned: false, agentCreated: false)], scope: resource)
                var rendered: [Data] = []
                for elapsed in [6.05, 6.35] {
                    sprite.previewElapsed = elapsed
                    let bitmap = render()
                    rendered.append(bitmap.representation(using: .png, properties: [:])!)
                }
                precondition(rendered[0] != rendered[1], "\(resource) must animate with unread \(kind)")
            }
            // Color/finish must not reset an event reaction or change its state.
            sprite.update(connected: true, connecting: false, working: 0,
                          items: [AttentionItem(id: "palette", fingerprint: "1", sessionId: "sample", title: "Sample", kind: "completion", summary: "Sample", pinned: false, agentCreated: false)], scope: resource)
            let baseline = sprite.playback.elapsed(at: ProcessInfo.processInfo.systemUptime)
            for palette in AvatarAppearance.palettes {
                sprite.load(shape, palette: palette.id, finish: finish, directory: resources)
                precondition(sprite.playback.state == .ready && sprite.playback.elapsed(at: ProcessInfo.processInfo.systemUptime) >= baseline)
            }
        }
    }
    // Exercise the real timer crossing the one-shot deadline, not only sampled
    // choreography. This runs in a synthetic offscreen native window.
    sprite.load("relay", directory: resources)
    sprite.previewElapsed = nil
    sprite.update(connected: true, connecting: false, working: 1,
        items: [AttentionItem(id: "timer", fingerprint: "1", sessionId: "sample", title: "Sample", kind: "session-error", summary: "Sample", pinned: false, agentCreated: false)], scope: "timer")
    sprite.animate(true)
    RunLoop.main.run(until: Date().addingTimeInterval(4.2))
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        precondition(sprite.animationTimerIsRunning, "Unread error must not stop the working timer")
    }
    sprite.animate(false); window.orderOut(nil)
    precondition(!sprite.animationTimerIsRunning)
    print("PASS: \(renderCount) native state/finish/shape renders, 24 mixed attention/work animations, timer continuity, transparent corners, full working decode, eight palettes, reaction continuity")
}
