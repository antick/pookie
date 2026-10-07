import CoreGraphics
import Foundation

/// Anything that can paint Pookie and report which pixels it painted.
///
/// M0 ships `CatRenderer` (procedural Core Graphics). M1 adds a SpriteKit
/// renderer for authored sprite sheets behind this same protocol, so the
/// behaviour engine and window shell never learn about either.
protocol PetRenderer {
    func draw(in context: CGContext, size: CGSize, pose: CatPose)
}

/// An 8-bit coverage map of the pet, used for silhouette hit-testing.
struct AlphaMask {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    /// `point` is in the renderer's own coordinate space, origin bottom-left,
    /// matching `CGContext` and an unflipped `NSView`.
    func isOpaque(at point: CGPoint) -> Bool {
        let x = Int(point.x.rounded(.down))
        let y = Int(point.y.rounded(.down))
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        return bytes[MaskRaster.index(x: x, y: y, width: width, height: height)] > MaskRaster.threshold
    }

    /// Coverage within `radius` pixels, used to add hysteresis to the
    /// mouse pass-through test so it cannot flicker on the cat's outline.
    func isOpaque(near point: CGPoint, radius: CGFloat) -> Bool {
        if isOpaque(at: point) { return true }
        for angle in stride(from: 0.0, to: 360.0, by: 45.0) {
            let radians = angle * .pi / 180
            let probe = CGPoint(
                x: point.x + cos(radians) * radius,
                y: point.y + sin(radians) * radius
            )
            if isOpaque(at: probe) { return true }
        }
        return false
    }
}

/// Rasterises an alpha-only bitmap and reads it back.
///
/// The one genuinely tricky part: `CGBitmapContext` draws with a bottom-left
/// origin, but its backing buffer is row-major from the *top*. Rather than
/// hardcode that assumption, `MaskRaster` probes it once at process start with
/// a 4x4 fill. If a future OS or a different bitmap info changes the layout,
/// hit-testing self-corrects instead of silently inverting vertically.
enum MaskRaster {
    static let threshold: UInt8 = 24

    /// True when buffer row 0 corresponds to the *bottom* of the image
    /// (i.e. no flip is needed to go from CG y to buffer row).
    static let rowZeroIsBottom: Bool = probeRowZeroIsBottom()

    static func index(x: Int, y: Int, width: Int, height: Int) -> Int {
        let row = rowZeroIsBottom ? y : (height - 1 - y)
        return row * width + x
    }

    /// Renders `renderer`'s output for `pose` into an alpha coverage map.
    ///
    /// No dilation pass. There used to be one — grow the silhouette a pixel so
    /// the cat is easier to grab — but `isOpaque(near:radius:)` already probes a
    /// 3 pt ring around the cursor, which does the same job with hysteresis,
    /// while the dilation cost ~90 ms per call in a debug build (measured): a
    /// visible five-frame stall twice a second, exactly while she was walking
    /// after a throw.
    static func make<R: PetRenderer>(renderer: R, size: CGSize, pose: CatPose) -> AlphaMask? {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        var buffer = [UInt8](repeating: 0, count: width * height)

        buffer.withUnsafeMutableBytes { raw -> Void in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ) else {
                return
            }
            context.setShouldAntialias(true)
            renderer.draw(in: context, size: CGSize(width: width, height: height), pose: pose)
        }

        return AlphaMask(width: width, height: height, bytes: buffer)
    }

    /// Empirically determine the buffer orientation. Fills the bottom half of a
    /// CG context and reports where those pixels landed.
    private static func probeRowZeroIsBottom() -> Bool {
        let width = 4, height = 4
        var buffer = [UInt8](repeating: 0, count: width * height)
        buffer.withUnsafeMutableBytes { raw -> Void in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ) else {
                return
            }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            // In CG coordinates this is the *bottom* half of the image.
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 2))
        }
        let rowZeroFilled = (0..<width).allSatisfy { buffer[0 * width + $0] > 127 }
        return rowZeroFilled
    }
}
