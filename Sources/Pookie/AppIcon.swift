import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Export options never change the running app's channel or preferences.
struct IconExportRequest {
    let path: String
    let identity: AppIdentity

    static func parse(arguments: [String]) throws -> IconExportRequest? {
        guard let index = arguments.firstIndex(of: "--render-icon") else {
            if arguments.contains("--icon-channel") { throw IconError.invalidArguments }
            return nil
        }
        guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--"), !arguments[index + 1].isEmpty else {
            throw IconError.invalidArguments
        }
        var identity = AppIdentity.current
        if let channelIndex = arguments.firstIndex(of: "--icon-channel") {
            guard channelIndex + 1 < arguments.count,
                  let channel = AppIdentity.Channel(rawValue: arguments[channelIndex + 1]) else {
                throw IconError.invalidArguments
            }
            identity = AppIdentity(
                bundleIdentifier: channel == .production ? AppIdentity.productionBundleIdentifier : AppIdentity.developmentBundleIdentifier,
                channel: channel.rawValue, isAppBundle: true
            )
        }
        return IconExportRequest(path: arguments[index + 1], identity: identity)
    }
}

enum IconError: Error, LocalizedError {
    case invalidArguments
    case renderingFailed
    case writingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments: return "Use --render-icon <png> [--icon-channel production|development]. The channel option is only for icon export."
        case .renderingFailed: return "Could not render the app icon."
        case .writingFailed(let path): return "Could not write the app icon to \(path)."
        }
    }
}

/// Uses the pet's own artwork, so the icon stays recognisably the same cat.
enum AppIcon {
    private enum Layout {
        static let pixels = 1024
        static let inset: CGFloat = 32
        static let cornerRadius: CGFloat = 210
        static let background: UInt32 = 0xFDF6EC
        static let badgeColor: UInt32 = 0x285D63
        static let catRect = CGRect(x: 26, y: 140, width: 972, height: 800)
        static let badgeRect = CGRect(x: 234, y: 70, width: 556, height: 164)
        static let badgeFontSize: CGFloat = 106
        static let badgeText = "DEV"
    }

    static func export(to path: String, identity: AppIdentity = .current) throws {
        guard let context = CGContext(data: nil, width: Layout.pixels, height: Layout.pixels,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw IconError.renderingFailed
        }
        context.setShouldAntialias(true)
        let canvas = CGRect(x: 0, y: 0, width: Layout.pixels, height: Layout.pixels)
        context.setFillColor(CGColor.hex(Layout.background))
        context.addPath(CGPath(roundedRect: canvas.insetBy(dx: Layout.inset, dy: Layout.inset),
                               cornerWidth: Layout.cornerRadius, cornerHeight: Layout.cornerRadius, transform: nil))
        context.fillPath()
        context.saveGState()
        context.translateBy(x: Layout.catRect.minX, y: Layout.catRect.minY)
        CatRenderer(palette: .tabby).draw(in: context, size: Layout.catRect.size, pose: CatPose())
        context.restoreGState()
        if !identity.isProduction { drawDevelopmentBadge(in: context) }

        guard let image = context.makeImage() else { throw IconError.renderingFailed }
        guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                               UTType.png.identifier as CFString, 1, nil) else {
            throw IconError.writingFailed(path)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw IconError.writingFailed(path) }
    }

    private static func drawDevelopmentBadge(in context: CGContext) {
        context.setFillColor(CGColor.hex(Layout.badgeColor))
        context.addPath(CGPath(roundedRect: Layout.badgeRect, cornerWidth: 44, cornerHeight: 44, transform: nil))
        context.fillPath()
        let text = NSAttributedString(string: Layout.badgeText, attributes: [
            .font: NSFont.systemFont(ofSize: Layout.badgeFontSize, weight: .heavy),
            .foregroundColor: NSColor.white,
        ])
        let size = text.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        text.draw(at: CGPoint(x: Layout.badgeRect.midX - size.width / 2, y: Layout.badgeRect.midY - size.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}
