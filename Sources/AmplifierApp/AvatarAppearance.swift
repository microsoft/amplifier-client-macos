#if os(macOS)
import AppKit
import CoreImage

@MainActor enum AvatarAppearance {
    /// Unit ink bounds, with a bottom-left origin for AppKit layout. Ignore faint
    /// edge pixels; a small animation allowance is added by the sprite view.
    static func inkBounds(_ image: CGImage) -> NSRect {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let found: NSRect? = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let pixels = buffer.bindMemory(to: UInt8.self)
            var left = width, right = 0, top = height, bottom = 0
            for y in 0..<height { for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 16 {
                left = min(left, x); right = max(right, x + 1)
                top = min(top, y); bottom = max(bottom, y + 1)
            } }
            guard right > left && bottom > top else { return nil }
            return NSRect(x: CGFloat(left) / CGFloat(width), y: 1 - CGFloat(bottom) / CGFloat(height),
                width: CGFloat(right - left) / CGFloat(width), height: CGFloat(bottom - top) / CGFloat(height))
        }
        return found ?? NSRect(x: 0, y: 0, width: 1, height: 1)
    }
    static let shapes = ["relay", "accord", "arc", "crest", "chord", "meter"]
    static func resourceName(_ shape: String, finish: String) -> String {
        let shape = shapes.contains(shape) ? shape : "relay"
        return shape + (finish == "dark" ? "-dark" : "")
    }
    struct Palette {
        let id: String
        let title: String
        let colors: [NSColor]
    }
    static let palettes: [Palette] = [
        .init(id: "blue", title: "Blue", colors: [NSColor(srgbRed: 0.04, green: 0.36, blue: 1, alpha: 1), .systemCyan]),
        .init(id: "cyan", title: "Cyan", colors: [.systemCyan, .systemTeal]),
        .init(id: "amber", title: "Amber", colors: [.systemOrange, .systemYellow]),
        .init(id: "crimson", title: "Crimson", colors: [.systemRed, .systemPink]),
        .init(id: "green", title: "Green", colors: [.systemGreen, .systemMint]),
        .init(id: "purple", title: "Purple", colors: [.systemPurple, .systemIndigo]),
        .init(id: "cyan-amber", title: "Cyan + amber", colors: [.systemCyan, .systemOrange]),
        .init(id: "purple-blue", title: "Purple + blue", colors: [.systemPurple, .systemBlue])
    ]
    static func palette(_ id: String) -> Palette { palettes.first { $0.id == id } ?? palettes[0] }
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static var cubes: [String: Data] = [:]
    /// Recolor the light channels at render time, preserving neutral glass,
    /// luminance detail, alpha, and the original animation's geometry.
    static func colored(_ source: CGImage, palette id: String) -> CGImage {
        let selected = palette(id)
        if cubes[selected.id] == nil {
            let n = 32
            var cube = [Float](); cube.reserveCapacity(n*n*n*4)
            let target = selected.colors.map { $0.usingColorSpace(.deviceRGB)! }
            for b in 0..<n { for g in 0..<n { for r in 0..<n {
                let color = NSColor(deviceRed: CGFloat(r)/31, green: CGFloat(g)/31, blue: CGFloat(b)/31, alpha: 1)
                var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
                color.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
                let dual = selected.id.contains("-")
                let secondary = h < 0.18 || h > 0.60
                let base = target[dual && secondary ? 1 : 0]
                var hue = base.hueComponent
                if !dual { hue += (h - 0.6) * 0.09; hue = (hue + 1).truncatingRemainder(dividingBy: 1) }
                let tint = NSColor(deviceHue: hue, saturation: s, brightness: v, alpha: 1)
                // Completely neutral facets stay neutral; very faint reflections
                // blend smoothly so a color change never paints over glass.
                let weight = min(1, s / 0.18)
                cube += [Float(color.redComponent*(1-weight)+tint.redComponent*weight),
                         Float(color.greenComponent*(1-weight)+tint.greenComponent*weight),
                         Float(color.blueComponent*(1-weight)+tint.blueComponent*weight), 1]
            } } }
            cubes[selected.id] = cube.withUnsafeBytes { Data($0) }
        }
        guard let filter = CIFilter(name: "CIColorCube") else { return source }
        filter.setValue(CIImage(cgImage: source), forKey: kCIInputImageKey)
        filter.setValue(32, forKey: "inputCubeDimension"); filter.setValue(cubes[selected.id], forKey: "inputCubeData")
        guard let output = filter.outputImage else { return source }
        return context.createCGImage(output, from: output.extent) ?? source
    }
    static func thumbnail(_ source: CGImage, palette: String) -> NSImage {
        let frame = source.width == 1536 && source.height == 2288
            ? source.cropping(to: CGRect(x: 0, y: 0, width: 192, height: 208))! : source
        // Cache actual thumbnail pixels, not full-size artwork with a small
        // logical size: exploring both finishes and all palettes stays bounded.
        let width = 156, height = 170
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return NSImage(cgImage: frame, size: NSSize(width: 78, height: 85)) }
        let scale = min(CGFloat(width) / CGFloat(frame.width), CGFloat(height) / CGFloat(frame.height))
        let size = NSSize(width: CGFloat(frame.width) * scale, height: CGFloat(frame.height) * scale)
        context.interpolationQuality = .high
        context.draw(frame, in: CGRect(x: (CGFloat(width) - size.width) / 2,
            y: (CGFloat(height) - size.height) / 2, width: size.width, height: size.height))
        return NSImage(cgImage: colored(context.makeImage()!, palette: palette), size: NSSize(width: 78, height: 85))
    }
}
#endif
