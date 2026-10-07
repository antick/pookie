import CoreGraphics

/// The expressive state the renderer draws. Deliberately flat and value-typed so
/// that M2's behaviour engine can produce poses without knowing anything about
/// AppKit, and so M1 can drive the same struct from SpriteKit.
enum CatMood: String {
    case idle
    case sleepy
    case happy
    case curious
    case alarmed
    case thinking
    case walking
    case dragged
}

/// The five shapes Pookie can wear.
///
/// `stand` is the M0 cat; the other four are the resting shapes. They are
/// anatomy keyframes, not sprites: see `CatAnatomy`.
enum CatShape: String, CaseIterable {
    case stand
    case sit
    case loaf
    case lie
    case stretch
}

/// How much of each shape she is currently wearing.
///
/// A weight *vector* rather than an enum plus a progress value, and that is the
/// whole trick behind "does not read as a hard cut": the renderer draws one cat
/// by averaging the shape anchors, so retargeting mid-transition — a cat that
/// sits down and then dozes off before the sit has finished — cannot pop,
/// because there is no from/to edge to re-anchor. Weights start at 1 on
/// `stand`, stay in 0...1, and keep summing to 1.
struct CatShapeWeights: Equatable {
    var stand: Double = 1
    var sit: Double = 0
    var loaf: Double = 0
    var lie: Double = 0
    var stretch: Double = 0

    subscript(shape: CatShape) -> Double {
        get {
            switch shape {
            case .stand: return stand
            case .sit: return sit
            case .loaf: return loaf
            case .lie: return lie
            case .stretch: return stretch
            }
        }
        set {
            switch shape {
            case .stand: stand = newValue
            case .sit: sit = newValue
            case .loaf: loaf = newValue
            case .lie: lie = newValue
            case .stretch: stretch = newValue
            }
        }
    }

    var total: Double { stand + sit + loaf + lie + stretch }

    /// The shape she is mostly wearing: for behaviour, logs and frame tiers.
    var dominant: CatShape {
        var best = CatShape.stand
        var bestWeight = -Double.infinity
        for shape in CatShape.allCases where self[shape] > bestWeight {
            best = shape
            bestWeight = self[shape]
        }
        return best
    }

    /// How much of the dominant shape she is wearing, 0...1.
    var dominantWeight: Double { self[dominant] }

    /// True once she has finished settling: no visible blend left.
    var isSettled: Bool { dominantWeight > 0.999 }

    /// All the way into `shape`, and nowhere else.
    static func only(_ shape: CatShape) -> CatShapeWeights {
        var weights = CatShapeWeights(stand: 0, sit: 0, loaf: 0, lie: 0)
        weights[shape] = 1
        return weights
    }

    /// Move toward `target` at a fixed rate: `step` is the *share of the whole*
    /// transferred by this call, so a settle over `1/step` calls has a definite
    /// end and `isSettled` means something.
    ///
    /// The other shapes give their weight up in proportion, which is what keeps
    /// a retarget smooth: a cat that sits down and then dozes off before the sit
    /// has finished keeps moving at the same speed instead of snapping.
    mutating func approach(_ target: CatShape, by step: Double) {
        let remaining = 1 - self[target]
        guard remaining > 0, step > 0 else { return }
        let move = min(remaining, step)
        let scale = (remaining - move) / remaining
        for shape in CatShape.allCases where shape != target {
            self[shape] *= scale
        }
        self[target] += move
    }

    /// Straight cross-fade, used to lay the scripted stretch over whatever
    /// resting shape she is already in.
    static func lerp(_ a: CatShapeWeights, _ b: CatShapeWeights, _ t: Double) -> CatShapeWeights {
        let t = min(max(t, 0), 1)
        var weights = CatShapeWeights(stand: 0, sit: 0, loaf: 0, lie: 0)
        for shape in CatShape.allCases {
            weights[shape] = a[shape] + (b[shape] - a[shape]) * t
        }
        return weights
    }
}

/// Every field here is intentionally cheap to compute and cheap to animate.
/// `CatRenderer` reads only this; nothing else.
struct CatPose {
    // Idle life signs
    var breathe: Double = 0          // -1...1, slow sine
    var blink: Double = 1            // 1 = open, 0 = fully closed
    var tailPhase: Double = 0        // radians, drives the tail sway
    var earTwitch: Double = 0        // radians

    // Body deformation, applied about the feet so the cat never floats
    var squash: Double = 1           // vertical scale
    var stretch: Double = 1          // horizontal scale
    var hopOffset: Double = 0        // design-space points, +up
    var tilt: Double = 0             // radians, about the feet

    // Orientation and attention
    var facing: Double = 1           // +1 right, -1 left
    /// Pupil offset in *design* space, so the facing flip mirrors it: `PetMotion`
    /// converts the screen-space aim before storing it here, and the renderer
    /// draws exactly what it is given.
    var gazeX: Double = 0            // -1...1
    var gazeY: Double = 0            // -1...1, no flip in y

    // Face details
    var mouthOpen: Double = 0        // 0...1, reserved for M2 speech
    var blush: Double = 0            // 0...1
    var mood: CatMood = .idle

    /// The resting shape she is wearing, blended across `CatShape`. Standing is
    /// the default, so a pose built by hand or by an old test is the M0 cat.
    var shape = CatShapeWeights()

    /// A neutral, awake, forward-facing cat.
    static let neutral = CatPose()
}

// MARK: - Render envelope

extension CatPose {
    /// The deformation range the renderer guarantees to draw without clipping.
    ///
    /// This is a contract, not a suggestion: `CatRenderer` clamps every pose to
    /// these limits before drawing, `CatGeometry.stage` is sized to contain the
    /// resulting ink, and `--selftest` sweeps the whole range and fails if a
    /// single pixel lands outside the stage. Motion code is free to ask for more
    /// squash than this; it just will not get it, and the cat will not lose an
    /// ear over it.
    enum RenderLimits {
        /// Radians of lean about the body, for a standing cat. The resting
        /// shapes scale this down by `CatAnatomy.leanScale`: they sit lower and
        /// wider, so the same angle would swing a loaf's belly through the
        /// ground line faster than it swings a standing cat's paws.
        static let tilt: Double = 0.16
        /// Horizontal scale bounds.
        static let minStretch: Double = 0.86
        static let maxStretch: Double = 1.16
        /// Vertical scale bounds.
        static let minSquash: Double = 0.84
        static let maxSquash: Double = 1.14
        /// Design-space points the body may be lifted off the ground.
        static let hop: Double = 3.4
        /// Radians of ear rotation.
        static let earTwitch: Double = 0.32
    }

    /// The pose as the renderer will actually draw it. Pure, so tests can assert
    /// that `clamped()` output is what the stage was measured against.
    func clampedForRender() -> CatPose {
        var clamped = self
        // Shape weights are an average, so a negative or absurd weight would
        // fold the anatomy inside out rather than merely exaggerate it. An
        // all-zero vector has no average at all, so it falls back to standing.
        // Clamped first: the lean limit depends on the shape she is wearing.
        for shape in CatShape.allCases {
            clamped.shape[shape] = min(max(clamped.shape[shape], 0), 1)
        }
        if clamped.shape.total <= 0.0001 { clamped.shape = CatShapeWeights() }

        let lean = RenderLimits.tilt * CatAnatomy.blend(clamped.shape).leanScale
        clamped.tilt = min(max(tilt, -lean), lean)
        clamped.stretch = min(max(stretch, RenderLimits.minStretch), RenderLimits.maxStretch)
        clamped.squash = min(max(squash, RenderLimits.minSquash), RenderLimits.maxSquash)
        clamped.hopOffset = min(max(hopOffset, 0), RenderLimits.hop)
        clamped.earTwitch = min(max(earTwitch, -RenderLimits.earTwitch), RenderLimits.earTwitch)
        clamped.breathe = min(max(breathe, -1), 1)
        clamped.blink = min(max(blink, 0), 1)
        clamped.gazeX = min(max(gazeX, -1), 1)
        clamped.gazeY = min(max(gazeY, -1), 1)
        clamped.mouthOpen = min(max(mouthOpen, 0), 1)
        clamped.blush = min(max(blush, 0), 1)
        return clamped
    }
}

/// Orange tabby, but the palette is injectable so skins are trivial later.
struct CatPalette {
    var fur: CGColor
    var furDark: CGColor
    var belly: CGColor
    var earInner: CGColor
    var outline: CGColor
    var eye: CGColor
    var eyeShine: CGColor
    var whisker: CGColor

    static let tabby = CatPalette(
        fur: .hex(0xF2A25C),
        furDark: .hex(0xD4803A),
        belly: .hex(0xFDEBD2),
        earInner: .hex(0xF7B9A0),
        outline: .hex(0x6B3F1D),
        eye: .hex(0x3A2E27),
        eyeShine: .hex(0xFFFFFF),
        whisker: .hex(0xFFFFFF, alpha: 0.85)
    )

    static let midnight = CatPalette(
        fur: .hex(0x6C7396),
        furDark: .hex(0x505778),
        belly: .hex(0xD9DCF0),
        earInner: .hex(0xE7B7C4),
        outline: .hex(0x2B2F45),
        eye: .hex(0x2A2438),
        eyeShine: .hex(0xFFFFFF),
        whisker: .hex(0xFFFFFF, alpha: 0.7)
    )
}
