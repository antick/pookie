import CoreGraphics
import Foundation

/// Canonical geometry for Pookie, in a 100x100 design space with the origin at
/// the bottom-left and the feet at `feetY`.
///
/// `CatRenderer` and the silhouette in `PetRenderer` both derive from these
/// constants, so changing a proportion cannot desynchronise the drawing from
/// its hit region. The *shape* of the cat — standing, sitting, loafing, lying,
/// stretching — is not here: that is `CatAnatomy`, a blendable table of anchors.
enum CatGeometry {
    static let design: CGFloat = 100
    static let feetY: CGFloat = 4

    /// Design units from the window's bottom edge up to the line she stands on:
    /// the bottom of her paw ink, outline stroke included.
    ///
    /// The physics floor is `PetMotion.origin.y`, and the window is drawn this
    /// much *lower* than that (see `PetMotion.windowOrigin`). The margin exists
    /// because the stage has to hold the parts that swing below her feet — a
    /// leaning paw, a loaf's wrapped tail — and without the offset that margin
    /// is visible: she hangs several points above every window top she perches
    /// on. Anchoring the window's bottom edge to the floor, as M0 did, is
    /// exactly that bug.
    ///
    /// 5.5 = the paw's resting bottom (`feetY`, 4) plus the stage's dip below
    /// the design origin (2.5), less the paw outline's half-width (1.0).
    /// `--selftest` measures the resting ink and fails if this drifts from it,
    /// at every size setting.
    static let groundInset: CGFloat = 5.5

    /// Lean pivots at the body's mass, not at the feet. Pivoting at the feet
    /// swings the (long, low) tail sideways, which was worth ~10 design units of
    /// extra stage width for the same visual lean — and the stage is the thing
    /// that decides how big the cat can be drawn.
    ///
    /// Each shape pivots about its own body centre; this is the standing one,
    /// kept as the documented default.
    static let tiltAnchor = CatAnatomy.stand.bodyCenter

    /// The design-space rect the renderer fits into the view.
    ///
    /// It is deliberately **larger than the 100x100 art box** and it is what the
    /// drawing is fitted to, so the parts that leave the box — the swaying tail
    /// on the left, the ears at the top of a hop or a landing squash — land
    /// inside the window instead of being cut off at its edge. The box is
    /// symmetric about x=50 so a left-facing cat has exactly the same room as a
    /// right-facing one.
    ///
    /// Design y=0 is still the cat's ground line: the stage only dips 2.5 units
    /// below it, for the lowest corner of a leaning paw, so the physics can keep
    /// treating the window's bottom edge as the floor.
    ///
    /// The numbers are not guesses: `--selftest` sweeps the whole
    /// `CatPose.RenderLimits` envelope — every shape keyframe and the blends
    /// between them — rasterises it, and fails if any ink lands outside this
    /// rect. Widen the limits and the test tells you to widen the stage. The
    /// resting shapes are wider and lower than the standing cat, which is what
    /// `CatAnatomy.leanScale` exists to pay for: without it they would push this
    /// rect (and the window size derived from it) outward.
    static let stage = CGRect(x: -18, y: -2.5, width: 136, height: 123)

    /// Window size that draws the cat at roughly the size it has always been,
    /// with the whole stage visible. Derived from the stage so the two cannot
    /// drift apart.
    static let preferredWindowSize = CGSize(
        width: (stage.width * 1.3).rounded(.up),
        height: (stage.height * 1.3).rounded(.up)
    )

    /// How design space maps into a view of a given size.
    struct Fit {
        var scale: CGFloat
        /// Where design point (0, 0) lands, in view coordinates.
        var origin: CGPoint

        func viewPoint(x: CGFloat, y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }
    }

    /// The pose transform, in design space, as a value.
    ///
    /// `applyPose` uses this, and so does the art-envelope check in
    /// `Diagnostics`, which means the test measures the transform the renderer
    /// actually applies rather than a copy of it that can drift. The chained
    /// `CGAffineTransform` form is verified to reproduce the equivalent
    /// `CGContext` call sequence exactly.
    ///
    /// The lean pivots about the *current* shape's body mass, so a loafed cat
    /// leans about a low, wide centre instead of swinging her head around a
    /// point up in the air where a standing cat's chest used to be.
    static func poseTransform(_ pose: CatPose) -> CGAffineTransform {
        let feet = CGPoint(x: design / 2, y: feetY)
        let pivot = CatAnatomy.blend(pose.shape).bodyCenter
        var transform = CGAffineTransform.identity

        transform = transform.translatedBy(x: 0, y: pose.hopOffset)

        transform = transform.translatedBy(x: pivot.x, y: pivot.y)
        transform = transform.rotated(by: pose.tilt)
        transform = transform.translatedBy(x: -pivot.x, y: -pivot.y)

        if pose.facing < 0 {
            transform = transform.translatedBy(x: design, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        }

        transform = transform.translatedBy(x: feet.x, y: feet.y)
        transform = transform.scaledBy(x: pose.stretch, y: pose.squash)
        transform = transform.translatedBy(x: -feet.x, y: -feet.y)
        return transform
    }

    /// Fit the stage inside `size` and centre it. A square window keeps a square
    /// cat; a non-square one letterboxes rather than stretching.
    static func fit(in size: CGSize) -> Fit {
        guard size.width > 0, size.height > 0 else {
            return Fit(scale: 0, origin: .zero)
        }
        let scale = min(size.width / stage.width, size.height / stage.height)
        return Fit(
            scale: scale,
            origin: CGPoint(
                x: (size.width - stage.width * scale) / 2 - stage.minX * scale,
                y: (size.height - stage.height * scale) / 2 - stage.minY * scale
            )
        )
    }
}

/// Draws Pookie procedurally.
///
/// The point of M0 is charm from code, not from art: squash and stretch,
/// breathing, tail sway, blinks and cursor-tracking eyes are all cheap to
/// compute and carry most of the personality. Authored sprite sheets land in M1
/// behind the same `PetRenderer` protocol.
///
/// Nothing here branches on posture: the shape arrives as a blend of
/// `CatAnatomy` anchors, and every part is drawn from those anchors. That is
/// what lets her sink into a loaf without a hard cut, and it keeps the posture
/// vocabulary in one table instead of spread through the drawing code.
struct CatRenderer: PetRenderer {
    var palette: CatPalette = .tabby
    var outlineWidth: CGFloat = 2.4

    func draw(in context: CGContext, size: CGSize, pose: CatPose) {
        // Clamp first: the stage below is sized for exactly this range, so a
        // wild pose from a producer becomes a slightly tamer cat rather than one
        // with an ear sliced off.
        let pose = pose.clampedForRender()
        let anatomy = CatAnatomy.blend(pose.shape)

        let fit = CatGeometry.fit(in: size)
        guard fit.scale > 0 else { return }

        context.saveGState()
        defer { context.restoreGState() }

        context.setShouldAntialias(true)
        context.setLineJoin(.round)
        context.setLineCap(.round)

        // Map design space into the view through the stage, which is centred in
        // the window.
        context.translateBy(x: fit.origin.x, y: fit.origin.y)
        context.scaleBy(x: fit.scale, y: fit.scale)

        applyPose(pose, to: context)

        drawTail(in: context, pose: pose, anatomy: anatomy)
        drawBody(in: context, pose: pose, anatomy: anatomy)
        drawPaws(in: context, anatomy: anatomy)
        drawEars(in: context, pose: pose, anatomy: anatomy)
        drawHead(in: context, pose: pose, anatomy: anatomy)
        drawFace(in: context, pose: pose, anatomy: anatomy)
        drawHeadStripes(in: context, anatomy: anatomy)
    }

    /// Applies `CatGeometry.poseTransform`, which is also what the art-envelope
    /// test uses. Order reads as: scale about the feet, flip, tilt about the
    /// body, then hop.
    private func applyPose(_ pose: CatPose, to context: CGContext) {
        context.concatenate(CatGeometry.poseTransform(pose))
    }

    // MARK: - Parts

    private func drawTail(in context: CGContext, pose: CatPose, anatomy: CatAnatomy) {
        let sway = sin(pose.tailPhase) * 0.40 * anatomy.tailSway
        let lift = cos(pose.tailPhase * 0.7) * 3.0 * anatomy.tailSway

        context.saveGState()
        // Pivot inside the body, so the visible tail swings from the rump
        // rather than detaching from it.
        context.translateBy(x: anatomy.tailBase.x, y: anatomy.tailBase.y)
        context.rotate(by: sway)
        context.translateBy(x: -anatomy.tailBase.x, y: -anatomy.tailBase.y)

        let path = CGMutablePath()
        path.move(to: anatomy.tailBase)
        path.addCurve(
            to: CGPoint(x: anatomy.tailTip.x, y: anatomy.tailTip.y + lift),
            control1: anatomy.tailControl1,
            control2: CGPoint(x: anatomy.tailControl2.x, y: anatomy.tailControl2.y + lift)
        )

        // Outline first as a wider stroke, then the fur on top: cheaper and
        // cleaner than computing an offset path.
        stroke(context, path: path, color: palette.outline, width: anatomy.tailOutlineWidth)
        stroke(context, path: path, color: palette.fur, width: anatomy.tailFurWidth)
        stroke(
            context,
            path: path,
            color: palette.furDark,
            width: anatomy.tailStripeWidth,
            dash: [2.4, 4.6],
            phase: 1.6
        )
        context.restoreGState()
    }

    private func drawBody(in context: CGContext, pose: CatPose, anatomy: CatAnatomy) {
        let breathe = CGFloat(pose.breathe) * 0.9
        let halfWidth = anatomy.bodyRadii.width
        let halfHeight = anatomy.bodyRadii.height
        let rect = CGRect(
            x: anatomy.bodyCenter.x - halfWidth,
            y: anatomy.bodyCenter.y - halfHeight + breathe * 0.5,
            width: halfWidth * 2,
            height: halfHeight * 2 + breathe
        )

        let path = CGPath(ellipseIn: rect, transform: nil)
        fillStroke(context, path: path, fill: palette.fur, stroke: palette.outline, width: outlineWidth)

        // Belly patch, clipped to the body so it always reads as fur markings.
        // Every ratio in here is the standing cat's number over the standing
        // cat's box, so a standing Pookie is unchanged by any of this.
        context.saveGState()
        context.addPath(path)
        context.clip()
        let belly = CGRect(
            x: anatomy.bodyCenter.x - halfWidth * (13.0 / 25),
            y: rect.minY - halfHeight * (4.0 / 19),
            width: halfWidth * (26.0 / 25),
            height: halfHeight * (22.0 / 19)
        )
        context.setFillColor(palette.belly)
        context.fillEllipse(in: belly)
        context.restoreGState()

        // Flank stripes. Placed low and to the sides so the head does not
        // cover them and so they read as tabby markings rather than shading.
        context.saveGState()
        context.addPath(path)
        context.clip()
        let stripeWidth = 3.2 * (halfHeight / 19)
        for direction in [CGFloat(-1), CGFloat(1)] {
            for offset in [CGFloat(14.0 / 25), CGFloat(20.0 / 25)] {
                let x = anatomy.bodyCenter.x + direction * offset * halfWidth
                let stripe = CGMutablePath()
                stripe.move(to: CGPoint(x: x, y: anatomy.bodyCenter.y + halfHeight * (8.0 / 19)))
                stripe.addQuadCurve(
                    to: CGPoint(
                        x: x + direction * halfWidth * (1.5 / 25),
                        y: anatomy.bodyCenter.y + halfHeight * (1.0 / 19)
                    ),
                    control: CGPoint(
                        x: x + direction * halfWidth * (4.0 / 25),
                        y: anatomy.bodyCenter.y + halfHeight * (4.5 / 19)
                    )
                )
                stroke(context, path: stripe, color: palette.furDark, width: stripeWidth)
            }
        }
        context.restoreGState()
    }

    /// Front paws. In the tucked shapes they land on top of the body silhouette
    /// and read as paws folded under the chest, which is what a loaf looks like
    /// from the front.
    private func drawPaws(in context: CGContext, anatomy: CatAnatomy) {
        for direction in [CGFloat(-1), CGFloat(1)] {
            let center = CGPoint(
                x: anatomy.bodyCenter.x + direction * anatomy.pawOffsetX,
                y: anatomy.pawCenterY
            )
            let rect = CGRect(
                x: center.x - anatomy.pawRadii.width,
                y: center.y - anatomy.pawRadii.height,
                width: anatomy.pawRadii.width * 2,
                height: anatomy.pawRadii.height * 2
            )
            let path = CGPath(ellipseIn: rect, transform: nil)
            fillStroke(context, path: path, fill: palette.belly, stroke: palette.outline, width: outlineWidth * 0.85)
        }
    }

    /// Ears are drawn *before* the head, so their bases tuck behind the skull.
    /// That overlap is what makes them read as attached rather than stuck on.
    private func drawEars(in context: CGContext, pose: CatPose, anatomy: CatAnatomy) {
        let scale = anatomy.headScale
        let twitch = CGFloat(pose.earTwitch)
        let flattened = pose.mood == .dragged || pose.mood == .alarmed
        let tipLift: CGFloat = (flattened ? 12 : 19) * scale

        for direction in [CGFloat(-1), CGFloat(1)] {
            let pivot = CGPoint(
                x: anatomy.headCenter.x + direction * 16 * scale,
                y: anatomy.headCenter.y + 12 * scale
            )
            context.saveGState()
            context.translateBy(x: pivot.x, y: pivot.y)
            context.rotate(by: direction * twitch)
            context.translateBy(x: -pivot.x, y: -pivot.y)

            let outer = CGMutablePath()
            outer.move(to: CGPoint(x: pivot.x + direction * 10 * scale, y: pivot.y - 10 * scale))
            outer.addLine(to: CGPoint(x: pivot.x - direction * 1.5 * scale, y: pivot.y + tipLift))
            outer.addLine(to: CGPoint(x: pivot.x - direction * 8 * scale, y: pivot.y + 8 * scale))
            outer.closeSubpath()
            fillStroke(context, path: outer, fill: palette.fur, stroke: palette.outline, width: outlineWidth)

            let inner = CGMutablePath()
            inner.move(to: CGPoint(x: pivot.x + direction * 5.5 * scale, y: pivot.y - 5.5 * scale))
            inner.addLine(to: CGPoint(x: pivot.x - direction * 1.5 * scale, y: pivot.y + tipLift - 7 * scale))
            inner.addLine(to: CGPoint(x: pivot.x - direction * 4.5 * scale, y: pivot.y + 4.5 * scale))
            inner.closeSubpath()
            context.setFillColor(palette.earInner)
            context.addPath(inner)
            context.fillPath()

            context.restoreGState()
        }
    }

    private func drawHead(in context: CGContext, pose: CatPose, anatomy: CatAnatomy) {
        let breathe = CGFloat(pose.breathe) * 0.4
        let radius = anatomy.headRadius
        let rect = CGRect(
            x: anatomy.headCenter.x - radius,
            y: anatomy.headCenter.y - radius + breathe * 0.4,
            width: radius * 2,
            height: radius * 2 + breathe
        )
        let path = CGPath(ellipseIn: rect, transform: nil)
        fillStroke(context, path: path, fill: palette.fur, stroke: palette.outline, width: outlineWidth)
    }

    /// How much of the yawn is showing, read straight off the stretch shape.
    ///
    /// The stretch timeline lives in `PetMotion`, as one shape weight; this is
    /// the renderer's reading of it. So the mouth opens as the bow deepens and
    /// shuts before she has finished standing up, with no second animation
    /// clock to keep in sync.
    static func yawnAmount(_ pose: CatPose) -> CGFloat {
        let weight = pose.shape.stretch
        let t = min(max((weight - 0.35) / 0.5, 0), 1)
        return CGFloat(t * t * (3 - 2 * t))
    }

    private func drawFace(in context: CGContext, pose: CatPose, anatomy: CatAnatomy) {
        let mood = pose.mood
        let yawn = Self.yawnAmount(pose)
        let awake = mood != .sleepy
        // A yawning cat squints: the two are one animation, not two.
        let blink = (awake ? max(0.0, min(1.0, pose.blink)) : 0.08) * (1 - 0.78 * Double(yawn))
        let eyeOpen = CGFloat(blink)
        let eyeRadius = anatomy.eyeRadius
        let headScale = anatomy.headScale

        for direction in [CGFloat(-1), CGFloat(1)] {
            let center = CGPoint(
                x: anatomy.headCenter.x + direction * anatomy.eyeOffsetX,
                y: anatomy.eyeY
            )

            if eyeOpen < 0.2 {
                // Closed: a single happy arc.
                let arc = CGMutablePath()
                arc.move(to: CGPoint(x: center.x - 5.5 * headScale, y: center.y))
                arc.addQuadCurve(
                    to: CGPoint(x: center.x + 5.5 * headScale, y: center.y),
                    control: CGPoint(x: center.x, y: center.y - 4.5 * headScale)
                )
                stroke(context, path: arc, color: palette.outline, width: 2.6 * headScale)
                continue
            }

            let height = eyeRadius * 2 * eyeOpen
            let eyeRect = CGRect(
                x: center.x - eyeRadius,
                y: center.y - height / 2,
                width: eyeRadius * 2,
                height: height
            )
            let eyePath = CGPath(ellipseIn: eyeRect, transform: nil)
            fillStroke(context, path: eyePath, fill: palette.belly, stroke: palette.outline, width: 1.8 * headScale)

            // Everything inside the eye is clipped to it: a real pupil slides to
            // the edge and is cut by the lid, and the cartoon pupil is wide
            // enough that without this it pokes through the outline at the far
            // end of the gaze.
            context.saveGState()
            context.addPath(eyePath)
            context.clip()

            // Pupil tracks the cursor, clamped inside the eye.
            let maxShift = eyeRadius - 2.2 * headScale
            let pupilRadius = eyeRadius * (mood == .alarmed ? 0.95 : 0.72)
            let pupilCenter = CGPoint(
                x: center.x + CGFloat(pose.gazeX) * maxShift,
                y: center.y + CGFloat(pose.gazeY) * (maxShift * 0.75) * eyeOpen
            )
            let pupilHeight = pupilRadius * 2 * max(0.35, eyeOpen)
            let pupilRect = CGRect(
                x: pupilCenter.x - pupilRadius,
                y: pupilCenter.y - pupilHeight / 2,
                width: pupilRadius * 2,
                height: pupilHeight
            )
            context.setFillColor(palette.eye)
            context.fillEllipse(in: pupilRect)

            // Highlight sits up and to the outside, which is what makes the
            // gaze direction legible at small sizes.
            let shine = CGPoint(
                x: pupilCenter.x + direction * 1.4 * headScale,
                y: pupilCenter.y + pupilHeight * 0.22
            )
            context.setFillColor(palette.eyeShine)
            context.fillEllipse(in: CGRect(
                x: shine.x - 1.5 * headScale,
                y: shine.y - 1.5 * headScale * eyeOpen,
                width: 3 * headScale,
                height: 3 * headScale * eyeOpen
            ))
            context.restoreGState()
        }

        // Muzzle, nose and mouth all hang off the muzzle anchor, so a smaller
        // resting head gets a proportionally smaller face.
        let muzzle = anatomy.muzzleCenter
        let muzzleRadii = anatomy.muzzleRadii
        let muzzleRect = CGRect(
            x: muzzle.x - muzzleRadii.width,
            y: muzzle.y - muzzleRadii.height,
            width: muzzleRadii.width * 2,
            height: muzzleRadii.height * 2
        )
        context.setFillColor(palette.belly)
        context.fillEllipse(in: muzzleRect)

        let noseWidth = muzzleRadii.width * (7.2 / 11)
        let noseHeight = muzzleRadii.height * (4.0 / 7.5)
        let noseBottom = muzzle.y - muzzleRadii.height * (2.6 / 7.5)
        let nose = CGMutablePath()
        nose.move(to: CGPoint(x: muzzle.x - noseWidth / 2, y: noseBottom + noseHeight))
        nose.addLine(to: CGPoint(x: muzzle.x + noseWidth / 2, y: noseBottom + noseHeight))
        nose.addLine(to: CGPoint(x: muzzle.x, y: noseBottom))
        nose.closeSubpath()
        fillStroke(context, path: nose, fill: .hex(0xE8867F), stroke: palette.outline, width: 1.6 * anatomy.muzzleScale)

        // Mouth. The open variant has to sit just under the nose, on the
        // muzzle — not down on the chest. `mouthOpen` is M2's speech; the yawn
        // is the shape weight, and they share one mouth.
        let mouthOpen = max(CGFloat(max(0, min(1, pose.mouthOpen))), yawn)
        if mouthOpen > 0.05 {
            let height = muzzleRadii.height * (7.0 / 7.5) * mouthOpen + 1
            let open = CGRect(
                x: muzzle.x - muzzleRadii.width * (5.0 / 11),
                y: muzzle.y - muzzleRadii.height * (8.5 / 7.5) - height / 2,
                width: muzzleRadii.width * (10.0 / 11),
                height: height
            )
            let openPath = CGPath(ellipseIn: open, transform: nil)
            fillStroke(context, path: openPath, fill: .hex(0xB4574F), stroke: palette.outline, width: 1.6 * anatomy.muzzleScale)
            // Tongue, because it is funny.
            if mouthOpen > 0.45 {
                let tongue = CGRect(
                    x: muzzle.x - muzzleRadii.width * (3.0 / 11),
                    y: muzzle.y - muzzleRadii.height * (11.5 / 7.5),
                    width: muzzleRadii.width * (6.0 / 11),
                    height: muzzleRadii.height * (3.4 / 7.5)
                )
                context.setFillColor(.hex(0xF08E93))
                context.fillEllipse(in: tongue)
            }
        } else {
            let mouthMid = noseBottom - muzzleRadii.height * (2.8 / 7.5)
            let cornerY = mouthMid - muzzleRadii.height * (1.4 / 7.5)
            let cornerX = muzzleRadii.width * (5.0 / 11)
            let controlY = mouthMid - muzzleRadii.height * (2.4 / 7.5)
            let controlOffsetX = muzzleRadii.width * (2.6 / 11)
            let mouth = CGMutablePath()
            mouth.move(to: CGPoint(x: muzzle.x, y: noseBottom))
            mouth.addLine(to: CGPoint(x: muzzle.x, y: mouthMid))
            mouth.move(to: CGPoint(x: muzzle.x, y: mouthMid))
            mouth.addQuadCurve(
                to: CGPoint(x: muzzle.x - cornerX, y: cornerY),
                control: CGPoint(x: muzzle.x - controlOffsetX, y: controlY)
            )
            mouth.move(to: CGPoint(x: muzzle.x, y: mouthMid))
            mouth.addQuadCurve(
                to: CGPoint(x: muzzle.x + cornerX, y: cornerY),
                control: CGPoint(x: muzzle.x + controlOffsetX, y: controlY)
            )
            stroke(context, path: mouth, color: palette.outline, width: 1.8 * anatomy.muzzleScale)
        }

        // Whiskers.
        let whiskerWidth = 1.3 * anatomy.muzzleScale
        for direction in [CGFloat(-1), CGFloat(1)] {
            for (index, dropPoint) in [CGFloat(2.4), 0, -2.4].enumerated() {
                let drop = dropPoint * (muzzleRadii.height / 7.5)
                let whisker = CGMutablePath()
                let startX = muzzle.x + direction * muzzleRadii.width * (8.0 / 11)
                let startY = muzzle.y - muzzleRadii.height * (1.0 / 7.5) + drop
                whisker.move(to: CGPoint(x: startX, y: startY))
                whisker.addQuadCurve(
                    to: CGPoint(
                        x: startX + direction * muzzleRadii.width * (20.0 / 11),
                        y: startY + drop * 0.6 + CGFloat(index) * 0.4 * (muzzleRadii.height / 7.5)
                    ),
                    control: CGPoint(
                        x: startX + direction * muzzleRadii.width,
                        y: startY + drop * 0.4 - 1.5 * (muzzleRadii.height / 7.5)
                    )
                )
                stroke(context, path: whisker, color: palette.whisker, width: whiskerWidth)
            }
        }

        // Blush.
        let blush = CGFloat(max(0, min(1, pose.blush)))
        if blush > 0.02 {
            context.setFillColor(.hex(0xF07A72, alpha: 0.45 * blush))
            for direction in [CGFloat(-1), CGFloat(1)] {
                let center = CGPoint(
                    x: anatomy.headCenter.x + direction * 16.5 * headScale,
                    y: anatomy.headCenter.y - 5 * headScale
                )
                context.fillEllipse(in: CGRect(
                    x: center.x - 5.5 * headScale,
                    y: center.y - 3 * headScale,
                    width: 11 * headScale,
                    height: 6 * headScale
                ))
            }
        }
    }

    private func drawHeadStripes(in context: CGContext, anatomy: CatAnatomy) {
        let scale = anatomy.headScale
        let top = anatomy.headCenter.y + anatomy.headRadius
        context.saveGState()
        let headPath = CGPath(
            ellipseIn: CGRect(
                x: anatomy.headCenter.x - anatomy.headRadius,
                y: anatomy.headCenter.y - anatomy.headRadius,
                width: anatomy.headRadius * 2,
                height: anatomy.headRadius * 2
            ),
            transform: nil
        )
        context.addPath(headPath)
        context.clip()

        for offset in [CGFloat(-7.5), 0, 7.5] {
            let stripe = CGMutablePath()
            let x = anatomy.headCenter.x + offset * scale
            stripe.move(to: CGPoint(x: x - 2 * scale, y: top - 3 * scale))
            stripe.addLine(to: CGPoint(x: x + 1.5 * scale, y: top - 10 * scale))
            stroke(context, path: stripe, color: palette.furDark, width: 2.6 * scale)
        }
        context.restoreGState()
    }

    // MARK: - Drawing helpers

    private func fillStroke(_ context: CGContext, path: CGPath, fill: CGColor, stroke strokeColor: CGColor, width: CGFloat) {
        context.saveGState()
        context.addPath(path)
        context.setFillColor(fill)
        context.fillPath()

        if width > 0 {
            context.addPath(path)
            context.setStrokeColor(strokeColor)
            context.setLineWidth(width)
            context.strokePath()
        }
        context.restoreGState()
    }

    private func stroke(
        _ context: CGContext,
        path: CGPath,
        color: CGColor,
        width: CGFloat,
        dash: [CGFloat]? = nil,
        phase: CGFloat = 0
    ) {
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(color)
        context.setLineWidth(width)
        if let dash {
            context.setLineDash(phase: phase, lengths: dash)
        }
        context.strokePath()
        context.restoreGState()
    }
}
