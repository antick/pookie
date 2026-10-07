import CoreGraphics

/// The anatomy of one cat shape: every anchor `CatRenderer` needs, in the
/// 100x100 design space, with the feet on `CatGeometry.feetY`.
///
/// A shape is *data*, not a branch. The renderer draws whatever anchors it is
/// handed, so settling into a loaf, dozing off into a lie, or stretching on
/// waking is an interpolation between two of these tables rather than a switch
/// in the drawing code. That is what stops a posture change reading as a hard
/// cut — and it is why there is one cat on screen at a time rather than two
/// cross-faded copies with their outlines showing through each other.
struct CatAnatomy {
    var bodyCenter: CGPoint
    var bodyRadii: CGSize

    var headCenter: CGPoint
    var headRadius: CGFloat

    var muzzleCenter: CGPoint
    var muzzleRadii: CGSize

    var eyeY: CGFloat
    var eyeOffsetX: CGFloat
    var eyeRadius: CGFloat

    /// Front paws. In the resting shapes they are drawn on top of the body
    /// silhouette, which is exactly what a tucked paw looks like head-on.
    var pawCenterY: CGFloat
    var pawOffsetX: CGFloat
    var pawRadii: CGSize

    /// The tail, as the cubic `CatRenderer` strokes. `lift` from the sway is
    /// added to `tailControl2` and `tailTip`, matching the original curve.
    var tailBase: CGPoint
    var tailControl1: CGPoint
    var tailControl2: CGPoint
    var tailTip: CGPoint
    var tailWidth: CGFloat
    /// Sway damping: a loafed tail twitches, it does not wag.
    var tailSway: Double
    /// Lean damping. The lean pivots about the body's mass, so the further the
    /// ink sits from that pivot the deeper the far edge swings; a low, wide loaf
    /// leaned as hard as a standing cat would grind its belly and its wrapped
    /// tail through the floor line, which is the window's bottom edge. Damping
    /// the lean by shape keeps the standing cat's 0.16 rad while keeping every
    /// resting shape inside the stage.
    var leanScale: Double

    /// Proportions the face is laid out with, so a smaller resting head keeps
    /// its features in proportion instead of sprouting a giant nose.
    var headScale: CGFloat { headRadius / 24 }
    var muzzleScale: CGFloat { muzzleRadii.width / 11 }

    /// Stroke widths for the tail's outline / fur / stripe passes, derived from
    /// one number so they cannot drift apart.
    var tailOutlineWidth: CGFloat { tailWidth }
    var tailFurWidth: CGFloat { tailWidth * 0.68 }
    var tailStripeWidth: CGFloat { tailWidth * 0.24 }

    /// The lowest point of the shape that is meant to be resting on the ground.
    ///
    /// Every shape must agree with `CatGeometry.feetY`: the physics treats the
    /// window's bottom edge as the floor, and a shape whose belly hovers would
    /// look like it was standing on nothing. The selftest pins this.
    var groundContact: CGFloat {
        min(bodyCenter.y - bodyRadii.height, pawCenterY - pawRadii.height)
    }

    // MARK: - Blending

    /// The same skeleton at a species' proportions.
    ///
    /// Every vertical anchor is scaled about `CatGeometry.feetY`, which is what
    /// keeps a small animal's feet on the ground line instead of floating: the
    /// species multiplies the distance from the floor, not the absolute
    /// coordinate.
    func wearing(_ traits: SpeciesTraits) -> CatAnatomy {
        func rise(_ y: CGFloat, _ factor: CGFloat) -> CGFloat {
            CatGeometry.feetY + (y - CatGeometry.feetY) * traits.scale * factor
        }
        func spread(_ x: CGFloat) -> CGFloat {
            CatGeometry.design / 2 + (x - CatGeometry.design / 2) * traits.scale
        }
        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: spread(p.x), y: rise(p.y, 1))
        }

        var anatomy = self
        // The body grows from its *underside*, which is the part that touches the
        // ground: scaling the centre and the radii by different factors — a
        // panda's body is wider and taller than a cat's — would otherwise push a
        // tall animal's belly through the floor and leave a short one hovering.
        let bodyUnderside = bodyCenter.y - bodyRadii.height
        anatomy.bodyRadii = CGSize(
            width: bodyRadii.width * traits.scale * traits.bodyWidth,
            height: bodyRadii.height * traits.scale * traits.bodyHeight
        )
        anatomy.bodyCenter = CGPoint(
            x: spread(bodyCenter.x),
            y: CatGeometry.feetY
                + (bodyUnderside - CatGeometry.feetY) * traits.scale
                + anatomy.bodyRadii.height
        )
        anatomy.headCenter = point(headCenter)
        anatomy.headRadius *= traits.scale * traits.headScale
        anatomy.muzzleCenter = point(muzzleCenter)
        anatomy.muzzleRadii = CGSize(
            width: muzzleRadii.width * traits.scale * traits.headScale * traits.muzzle,
            height: muzzleRadii.height * traits.scale * traits.headScale * traits.muzzle
        )
        anatomy.eyeY = rise(eyeY, traits.headScale)
        anatomy.eyeOffsetX *= traits.scale * traits.headScale
        anatomy.eyeRadius *= traits.scale * traits.headScale
        anatomy.pawCenterY = rise(pawCenterY, 1)
        anatomy.pawOffsetX *= traits.scale
        anatomy.pawRadii = CGSize(
            width: pawRadii.width * traits.scale,
            height: pawRadii.height * traits.scale
        )
        // The tail is the one part that scales along its own length rather than
        // about the floor: an animal's tail is longer, not further up.
        let tailBasePoint = point(tailBase)
        func tailPoint(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: tailBasePoint.x + (p.x - tailBase.x) * traits.scale * traits.tailScale,
                y: tailBasePoint.y + (p.y - tailBase.y) * traits.scale * traits.tailScale
            )
        }
        let lift = traits.tailLift * traits.scale
        anatomy.tailBase = tailBasePoint
        anatomy.tailControl1 = CGPoint(x: tailPoint(tailControl1).x, y: tailPoint(tailControl1).y + lift * 0.3)
        anatomy.tailControl2 = CGPoint(x: tailPoint(tailControl2).x, y: tailPoint(tailControl2).y + lift * 0.7)
        anatomy.tailTip = CGPoint(x: tailPoint(tailTip).x, y: tailPoint(tailTip).y + lift)
        anatomy.tailWidth *= traits.scale * traits.tailWidth
        // A wider animal leans less, for exactly the reason a loaf does: the
        // further the ink sits from the pivot, the deeper the far edge swings,
        // and a panda's is a long way out.
        anatomy.leanScale /= pow(max(1, traits.bodyWidth), 1.5)
        return anatomy
    }

    /// The weighted average of the shape keyframes: one cat, no cross-fade.
    static func blend(_ weights: CatShapeWeights) -> CatAnatomy {
        var total: Double = 0
        for shape in CatShape.allCases { total += max(0, weights[shape]) }
        guard total > 0.0001 else { return .stand }

        var result = CatAnatomy.zero
        for shape in CatShape.allCases {
            let weight = max(0, weights[shape]) / total
            guard weight > 0 else { continue }
            result.add(keyframe(shape), scaledBy: weight)
        }
        return result
    }

    /// The keyframe for a single shape, used by the selftest and the blend.
    static func keyframe(_ shape: CatShape) -> CatAnatomy {
        switch shape {
        case .stand: return .stand
        case .sit: return .sit
        case .loaf: return .loaf
        case .lie: return .lie
        case .stretch: return .stretch
        }
    }

    /// The additive identity for `blend`. Every field is zero — including
    /// `leanScale`, which is a *weighted average* like the rest, not a factor
    /// that starts at 1.
    private static let zero = CatAnatomy(
        bodyCenter: .zero, bodyRadii: .zero,
        headCenter: .zero, headRadius: 0,
        muzzleCenter: .zero, muzzleRadii: .zero,
        eyeY: 0, eyeOffsetX: 0, eyeRadius: 0,
        pawCenterY: 0, pawOffsetX: 0, pawRadii: .zero,
        tailBase: .zero, tailControl1: .zero, tailControl2: .zero, tailTip: .zero,
        tailWidth: 0, tailSway: 0, leanScale: 0
    )

    private mutating func add(_ other: CatAnatomy, scaledBy weight: Double) {
        let weight = CGFloat(weight)
        bodyCenter.add(other.bodyCenter, scaledBy: weight)
        bodyRadii.add(other.bodyRadii, scaledBy: weight)
        headCenter.add(other.headCenter, scaledBy: weight)
        headRadius += other.headRadius * weight
        muzzleCenter.add(other.muzzleCenter, scaledBy: weight)
        muzzleRadii.add(other.muzzleRadii, scaledBy: weight)
        eyeY += other.eyeY * weight
        eyeOffsetX += other.eyeOffsetX * weight
        eyeRadius += other.eyeRadius * weight
        pawCenterY += other.pawCenterY * weight
        pawOffsetX += other.pawOffsetX * weight
        pawRadii.add(other.pawRadii, scaledBy: weight)
        tailBase.add(other.tailBase, scaledBy: weight)
        tailControl1.add(other.tailControl1, scaledBy: weight)
        tailControl2.add(other.tailControl2, scaledBy: weight)
        tailTip.add(other.tailTip, scaledBy: weight)
        tailWidth += other.tailWidth * weight
        tailSway += other.tailSway * weight
        leanScale += other.leanScale * weight
    }
}

// MARK: - The keyframes

extension CatAnatomy {
    /// The M0 cat. Every other shape is a move away from these numbers, so a
    /// standing Pookie with default weights is pixel-for-pixel the cat that
    /// shipped before this file existed.
    static let stand = CatAnatomy(
        bodyCenter: CGPoint(x: 50, y: 36),
        bodyRadii: CGSize(width: 25, height: 19),
        headCenter: CGPoint(x: 50, y: 66),
        headRadius: 24,
        muzzleCenter: CGPoint(x: 50, y: 56),
        muzzleRadii: CGSize(width: 11, height: 7.5),
        eyeY: 70,
        eyeOffsetX: 10,
        eyeRadius: 5.6,
        pawCenterY: 11,
        pawOffsetX: 12,
        pawRadii: CGSize(width: 8.5, height: 7),
        tailBase: CGPoint(x: 33, y: 27),
        tailControl1: CGPoint(x: 11, y: 23),
        tailControl2: CGPoint(x: 1, y: 45),
        tailTip: CGPoint(x: 17, y: 61),
        tailWidth: 12.5,
        tailSway: 1,
        leanScale: 1
    )

    /// Sitting up: the chest stays tall, the rump is down on the ground, the
    /// front paws come closer together, and the tail curls around the front.
    /// This is what she does *before* she falls asleep — still awake, no longer
    /// standing.
    static let sit = CatAnatomy(
        bodyCenter: CGPoint(x: 50, y: 25.5),
        bodyRadii: CGSize(width: 23, height: 21.5),
        headCenter: CGPoint(x: 50, y: 63),
        headRadius: 23.5,
        muzzleCenter: CGPoint(x: 50, y: 53.5),
        muzzleRadii: CGSize(width: 10.7, height: 7.2),
        eyeY: 67,
        eyeOffsetX: 9.7,
        eyeRadius: 5.5,
        pawCenterY: 10.6,
        pawOffsetX: 8.5,
        pawRadii: CGSize(width: 7.6, height: 6.6),
        tailBase: CGPoint(x: 31, y: 22),
        tailControl1: CGPoint(x: 14, y: 25),
        tailControl2: CGPoint(x: 8, y: 15),
        tailTip: CGPoint(x: 30, y: 10),
        tailWidth: 11,
        tailSway: 0.55,
        leanScale: 0.34
    )

    /// The tucked-paw loaf: a low wide bun, head settled down onto it, front
    /// paws drawn as two small shapes tucked under the chest, tail wrapped
    /// along the ground in front. The single biggest "it's a creature" upgrade
    /// in the whole renderer.
    static let loaf = CatAnatomy(
        bodyCenter: CGPoint(x: 50, y: 21),
        bodyRadii: CGSize(width: 31, height: 16),
        headCenter: CGPoint(x: 50, y: 52),
        headRadius: 22,
        muzzleCenter: CGPoint(x: 50, y: 43),
        muzzleRadii: CGSize(width: 10.2, height: 6.9),
        eyeY: 56,
        eyeOffsetX: 9.2,
        eyeRadius: 5.2,
        pawCenterY: 9,
        pawOffsetX: 9.5,
        pawRadii: CGSize(width: 8, height: 5),
        tailBase: CGPoint(x: 30, y: 20),
        tailControl1: CGPoint(x: 13, y: 23),
        tailControl2: CGPoint(x: 8, y: 14),
        tailTip: CGPoint(x: 28, y: 10),
        tailWidth: 11.5,
        tailSway: 0.3,
        leanScale: 0.30
    )

    /// Asleep: flatter than the loaf, head down and forward, eyes shut, tail
    /// curled in. Pairs with `CatMood.sleepy` and the low frame tier.
    static let lie = CatAnatomy(
        bodyCenter: CGPoint(x: 50, y: 16.5),
        bodyRadii: CGSize(width: 33, height: 12.5),
        headCenter: CGPoint(x: 50, y: 40),
        headRadius: 21,
        muzzleCenter: CGPoint(x: 50, y: 31),
        muzzleRadii: CGSize(width: 9.8, height: 6.6),
        eyeY: 44,
        eyeOffsetX: 8.8,
        eyeRadius: 5,
        pawCenterY: 8.5,
        pawOffsetX: 10,
        pawRadii: CGSize(width: 7.5, height: 4.5),
        tailBase: CGPoint(x: 28, y: 16),
        tailControl1: CGPoint(x: 12, y: 18),
        tailControl2: CGPoint(x: 8, y: 12),
        tailTip: CGPoint(x: 26, y: 10),
        tailWidth: 11,
        tailSway: 0.2,
        leanScale: 0.25
    )

    /// The wake-up bow: rump up, chest low, front paws pushed forward, tail
    /// straight up. The open mouth and the squint that go with it are the
    /// renderer's reading of how much of this shape she is wearing; see
    /// `CatRenderer.drawFace`.
    static let stretch = CatAnatomy(
        bodyCenter: CGPoint(x: 50, y: 31),
        bodyRadii: CGSize(width: 27, height: 18),
        headCenter: CGPoint(x: 50, y: 54),
        headRadius: 23,
        muzzleCenter: CGPoint(x: 50, y: 45),
        muzzleRadii: CGSize(width: 10.5, height: 7.1),
        eyeY: 58,
        eyeOffsetX: 9.5,
        eyeRadius: 5.5,
        pawCenterY: 10,
        pawOffsetX: 15,
        pawRadii: CGSize(width: 9.5, height: 6),
        tailBase: CGPoint(x: 35, y: 26),
        tailControl1: CGPoint(x: 15, y: 33),
        tailControl2: CGPoint(x: 7, y: 57),
        tailTip: CGPoint(x: 24, y: 76),
        tailWidth: 12,
        tailSway: 0.8,
        leanScale: 0.80
    )
}

// MARK: - Small vector helpers

private extension CGPoint {
    mutating func add(_ other: CGPoint, scaledBy weight: CGFloat) {
        x += other.x * weight
        y += other.y * weight
    }
}

private extension CGSize {
    mutating func add(_ other: CGSize, scaledBy weight: CGFloat) {
        width += other.width * weight
        height += other.height * weight
    }
}
