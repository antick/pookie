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

    /// The teleport blink: 0 is an ordinary cat, 1 is a cat who is not there.
    ///
    /// One number for the whole effect. The renderer spins her down to nothing as
    /// this rises and throws a little light and fur off her feet; the behaviour
    /// plays it 0 → 1, moves her, then 1 → 0, so the twist unwinds on the way in
    /// and there is no second number to keep in sync.
    ///
    /// Deliberately not `stretch`/`squash`: those are clamped to the art
    /// envelope, and this one has to reach zero, which is the entire point.
    var vanish: Double = 0

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

    /// What kind of animal she is. The renderer draws whatever this names, so a
    /// species is a value change rather than a different code path everywhere.
    var species: PetSpecies = .cat

    /// Wing flap, 0 (folded) to 1 (up). A bird walks with a little flutter and
    /// flies with a full flap; for everyone else this stays at zero and nothing
    /// is drawn.
    var flap: Double = 0

    /// A neutral, awake, forward-facing cat.
    static let neutral = CatPose()
}

extension CatPose {
    /// The skeleton this pose is drawn with: the blended shapes, at the species'
    /// proportions.
    ///
    /// One place applies the species, so nothing can forget to — and the art
    /// envelope, the pose transform, the gaze anchor and the bubble all agree
    /// about where the animal's head is.
    var anatomy: CatAnatomy {
        CatAnatomy.blend(shape).wearing(species.traits)
    }
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

        let lean = RenderLimits.tilt * clamped.anatomy.leanScale
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
        clamped.vanish = min(max(vanish, 0), 1)
        return clamped
    }
}

/// Every colour the cat is painted with. Injectable, because a desk with more
/// than one cat on it needs them to look like different cats — see `CatSkin`.
struct CatPalette {
    var fur: CGColor
    var furDark: CGColor
    /// Chest, muzzle, paws and the white of the eye. This one field does a lot of
    /// work: a tuxedo is mostly this colour with dark fur on top.
    var belly: CGColor
    var earInner: CGColor
    var outline: CGColor
    var eye: CGColor
    var eyeShine: CGColor
    var whisker: CGColor
    var nose: CGColor
    var mouth: CGColor
    var tongue: CGColor
    var blush: CGColor

    /// Build a coat from one line of numbers.
    static func coat(
        fur: UInt32,
        furDark: UInt32,
        belly: UInt32,
        earInner: UInt32,
        outline: UInt32,
        eye: UInt32,
        nose: UInt32,
        mouth: UInt32,
        tongue: UInt32,
        blush: UInt32,
        whiskerAlpha: Double = 0.85,
        eyeShine: UInt32 = 0xFFFFFF
    ) -> CatPalette {
        CatPalette(
            fur: .hex(fur),
            furDark: .hex(furDark),
            belly: .hex(belly),
            earInner: .hex(earInner),
            outline: .hex(outline),
            eye: .hex(eye),
            eyeShine: .hex(eyeShine),
            whisker: .hex(0xFFFFFF, alpha: whiskerAlpha),
            nose: .hex(nose),
            mouth: .hex(mouth),
            tongue: .hex(tongue),
            blush: .hex(blush)
        )
    }
}

/// A coat, which is also an identity: `PetCohort` hands out a different one to
/// each pet it spawns, because two identical cats on one desk read as a rendering
/// bug rather than as two pets. Ten of them, one for each pet the settings allow.
enum CatSkin: String, CaseIterable {
    case tabby
    case midnight
    case tuxedo
    case ginger
    case cream
    case calico
    case siamese
    case grey
    case chocolate
    case snow
    /// White with black points: the coat a panda is read from.
    case panda
    /// Duckling yellow, with an orange bill and feet: `nose` is the bill.
    case duckling
    /// Warm brown, for a bear.
    case cocoa
    /// Sandy gold, for a hamster.
    case hazel

    var name: String {
        switch self {
        case .tabby: return "Tabby"
        case .midnight: return "Midnight"
        case .tuxedo: return "Tuxedo"
        case .ginger: return "Ginger"
        case .cream: return "Cream"
        case .calico: return "Calico"
        case .siamese: return "Siamese"
        case .grey: return "Grey"
        case .chocolate: return "Chocolate"
        case .snow: return "Snow"
        case .panda: return "Panda"
        case .duckling: return "Duckling"
        case .cocoa: return "Cocoa"
        case .hazel: return "Hazel"
        }
    }

    var palette: CatPalette {
        switch self {
        case .tabby:
            return .coat(
                fur: 0xF2A25C, furDark: 0xD4803A, belly: 0xFDEBD2, earInner: 0xF7B9A0,
                outline: 0x6B3F1D, eye: 0x3A2E27, nose: 0xE8867F, mouth: 0xB4574F,
                tongue: 0xF08E93, blush: 0xF07A72
            )
        case .midnight:
            return .coat(
                fur: 0x6C7396, furDark: 0x505778, belly: 0xD9DCF0, earInner: 0xE7B7C4,
                outline: 0x2B2F45, eye: 0x2A2438, nose: 0xD9A0A8, mouth: 0x6E4F63,
                tongue: 0xE7B7C4, blush: 0xC98BA8, whiskerAlpha: 0.7
            )
        case .tuxedo:
            return .coat(
                fur: 0x33364A, furDark: 0x24273A, belly: 0xF7F4EC, earInner: 0xE0A2A2,
                outline: 0x14161F, eye: 0x3E5B45, nose: 0x3A3A3A, mouth: 0x5E5148,
                tongue: 0xE89AA0, blush: 0xD98A8A, whiskerAlpha: 0.9
            )
        case .ginger:
            return .coat(
                fur: 0xE8794A, furDark: 0xC25A32, belly: 0xFBE3CC, earInner: 0xF0A78F,
                outline: 0x7A3A1C, eye: 0x4A3A22, nose: 0xD97A6A, mouth: 0xA64A3F,
                tongue: 0xEE8F8A, blush: 0xE0766A
            )
        case .cream:
            return .coat(
                fur: 0xF0D7B0, furDark: 0xDCBE92, belly: 0xFBF3E2, earInner: 0xEFB9AE,
                outline: 0x8A6A45, eye: 0x4C4034, nose: 0xE9A79E, mouth: 0xB4746A,
                tongue: 0xF2A9A2, blush: 0xEFA79A
            )
        case .calico:
            return .coat(
                fur: 0xF5EDE0, furDark: 0xD97B3F, belly: 0xFFFFFA, earInner: 0xEFA79A,
                outline: 0x7A5A3E, eye: 0x6B4A22, nose: 0xE8938C, mouth: 0xB06A62,
                tongue: 0xF0A29B, blush: 0xEA8F86
            )
        case .siamese:
            return .coat(
                fur: 0xE8D6BB, furDark: 0x5A4433, belly: 0xF7EDDC, earInner: 0xD9A08F,
                outline: 0x4A3628, eye: 0x4A6BA8, nose: 0x6B5140, mouth: 0x4E3A2E,
                tongue: 0xD98F94, blush: 0xC98A86
            )
        case .grey:
            return .coat(
                fur: 0x9AA0A8, furDark: 0x7C828C, belly: 0xE8E9EB, earInner: 0xC9A8AC,
                outline: 0x4A4E55, eye: 0x3C4A55, nose: 0x8A8F95, mouth: 0x5A5F66,
                tongue: 0xC98F94, blush: 0xB08A8E
            )
        case .chocolate:
            return .coat(
                fur: 0x6B4A34, furDark: 0x523827, belly: 0xD9BFA6, earInner: 0xC99A86,
                outline: 0x33231A, eye: 0x6A4A20, nose: 0x4A342A, mouth: 0x3E2C22,
                tongue: 0xD98F86, blush: 0xB07A72
            )
        case .snow:
            return .coat(
                fur: 0xF7F4EE, furDark: 0xE0DAD0, belly: 0xFFFFFF, earInner: 0xF2B7B2,
                outline: 0x8A8580, eye: 0x5A7FA8, nose: 0xED9AA0, mouth: 0xB4747A,
                tongue: 0xF0A0A8, blush: 0xEFA0A0
            )
        case .panda:
            // `furDark` is the black: ears, eye patches, paws and the tail
            // stripes, which is why the panda species draws those parts from the
            // flank colour rather than the belly.
            return .coat(
                fur: 0xF6F2EA, furDark: 0x2A2A2E, belly: 0xFFFDF8, earInner: 0x2A2A2E,
                outline: 0x1A1A1E, eye: 0x232326, nose: 0x232326, mouth: 0x3A3A3E,
                tongue: 0xD98F94, blush: 0xD9A0A0, whiskerAlpha: 0.5
            )
        case .duckling:
            // The bill and the webbed feet are drawn from `nose`, so this coat's
            // orange is the whole duckling.
            return .coat(
                fur: 0xF7D64C, furDark: 0xE8BE33, belly: 0xFFF3B8, earInner: 0xF0C84A,
                outline: 0xC9A02A, eye: 0x2E2A26, nose: 0xF08A2B, mouth: 0xC96A1E,
                tongue: 0xF0A0A8, blush: 0xF2A0A0
            )
        case .cocoa:
            return .coat(
                fur: 0xA9744C, furDark: 0x8A5B38, belly: 0xE8C9A8, earInner: 0xD9A98A,
                outline: 0x5E3D26, eye: 0x4A3520, nose: 0x3A2A1E, mouth: 0x7A5A44,
                tongue: 0xE09090, blush: 0xE0A090
            )
        case .hazel:
            return .coat(
                fur: 0xD9A96A, furDark: 0xC08F4E, belly: 0xFFF2DC, earInner: 0xF0B8B0,
                outline: 0x8A6A3E, eye: 0x3A2A20, nose: 0xE39A9A, mouth: 0xA9705A,
                tongue: 0xF0A0A8, blush: 0xEFA8A0
            )
        }
    }
}

extension CatPalette {
    /// The default coat. `CatSkin` owns the colours; this is the convenience the
    /// tests and the defaults use.
    static var tabby: CatPalette { CatSkin.tabby.palette }
}
