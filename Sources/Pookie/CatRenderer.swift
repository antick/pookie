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
        let pivot = pose.anatomy.bodyCenter
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

    /// The teleport blink, as a transform: she spins and shrinks to nothing.
    ///
    /// Separate from `poseTransform` and public for the same reason that one is:
    /// the art-envelope test has to bound the transform the renderer actually
    /// applies, and this one takes her somewhere the deformation limits do not —
    /// all the way to nothing.
    ///
    /// The shrink leads the spin on purpose, and the spin is a *quarter* turn.
    ///
    /// The cat is nearly as tall as the room the stage leaves above the floor, so
    /// a full turn at full size would sweep her head through the ground line. The
    /// two levers are coupled: the further the turn has gone, the smaller she has
    /// to be, and a larger turn reaches its dangerous angle sooner — which costs
    /// her visibility, because the shrink has to be front-loaded to pay for it.
    /// A quarter turn with a square shrink keeps a readable cat for the first half
    /// of the blink and lands the widest shape (a lie's wrapped tail) with a
    /// design unit to spare. Turn further and the lie wraps underground.
    ///
    /// The composition reads as: scale about the body's centre, then rotate about
    /// it (the first call is the last thing applied to the point, exactly as in
    /// `poseTransform`).
    static func vanishTransform(_ pose: CatPose) -> CGAffineTransform {
        let vanish = min(max(pose.vanish, 0), 1)
        guard vanish > 0.0001 else { return .identity }

        let pivot = pose.anatomy.bodyCenter
        let scale = CGFloat((1 - vanish) * (1 - vanish))
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: pivot.x, y: pivot.y)
        transform = transform.rotated(by: CGFloat(vanish) * .pi / 2)
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: -pivot.x, y: -pivot.y)
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
        let anatomy = pose.anatomy

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

        // The poof goes down before she does: light and fur coming off her feet,
        // drawn in design space so it stays on the ground while she twists.
        drawBlinkEffect(in: context, pose: pose)

        applyPose(pose, to: context)
        context.concatenate(CatGeometry.vanishTransform(pose))

        drawTail(in: context, pose: pose, anatomy: anatomy)
        drawBody(in: context, pose: pose, anatomy: anatomy)
        // Wings sit on the flank, so they go over the body and under the head.
        drawWings(in: context, pose: pose, anatomy: anatomy)
        if pose.species.traits.spikes { drawSpikes(in: context, anatomy: anatomy) }
        drawPaws(in: context, pose: pose, anatomy: anatomy)
        drawPattern(in: context, pose: pose, anatomy: anatomy)
        // Over the paws: a thrown foreleg is in front of the body, not behind it.
        if pose.punch != 0 { drawPunch(in: context, pose: pose, anatomy: anatomy) }
        drawEars(in: context, pose: pose, anatomy: anatomy)
        drawHead(in: context, pose: pose, anatomy: anatomy)
        if pose.species.traits.gills { drawGills(in: context, pose: pose, anatomy: anatomy) }
        drawFacePattern(in: context, pose: pose, anatomy: anatomy)
        if pose.species.traits.cheekRuff { drawCheekRuff(in: context, anatomy: anatomy) }
        if pose.species.traits.cheeks { drawCheeks(in: context, anatomy: anatomy) }
        drawFace(in: context, pose: pose, anatomy: anatomy)
        drawHeadStripes(in: context, pose: pose, anatomy: anatomy)
    }

    /// Applies `CatGeometry.poseTransform`, which is also what the art-envelope
    /// test uses. Order reads as: scale about the feet, flip, tilt about the
    /// body, then hop.
    private func applyPose(_ pose: CatPose, to context: CGContext) {
        context.concatenate(CatGeometry.poseTransform(pose))
    }

    // MARK: - Parts

    /// The blink's poof: two rings on the ground and a handful of sparks.
    ///
    /// Deliberately tiny — two stroked ellipses and seven short lines, and only
    /// while she is actually blinking (under a second, once every minute or two).
    /// The cheapest thing that reads as magic rather than as a window being
    /// redrawn somewhere else, and it needs no new field beyond `vanish`.
    private func drawBlinkEffect(in context: CGContext, pose: CatPose) {
        let vanish = CGFloat(min(max(pose.vanish, 0), 1))
        // Strongest half way through and nothing at either end, so one curve
        // serves leaving and arriving alike.
        let intensity = CGFloat(sin(Double(vanish) * Double.pi))
        guard intensity > 0.02 else { return }

        // Everything here is squashed toward the ground plane and the reach is
        // kept inside the stage: the ink sweep in `--selftest` fails if the poof
        // so much as touches the window edge, and it is the only pose the
        // deformation limits do not bound.
        let centre = CGPoint(x: CatGeometry.design / 2, y: CatGeometry.feetY + 4)

        // Two rings, opening as she leaves and closing as she arrives.
        for (index, ring) in [CGFloat(1), CGFloat(0.62)].enumerated() {
            let radius = (9 + 18 * vanish) * ring
            let alpha = intensity * (index == 0 ? 0.5 : 0.75)
            context.setStrokeColor(CGColor.hex(0xFFE9A8, alpha: alpha))
            context.setLineWidth(2.4 - CGFloat(index) * 0.7)
            context.strokeEllipse(in: CGRect(
                x: centre.x - radius,
                y: centre.y - radius * 0.25,
                width: radius * 2,
                height: radius * 0.5
            ))
        }

        // Fur and sparks thrown outward. Her own colour, because the joke is that
        // the cat is coming apart into fluff.
        for index in 0..<7 {
            let angle = Double(index) / 7 * 2 * Double.pi + Double(vanish) * 0.9
            let inner = 11 + 18 * vanish
            let outer = inner + 4 + 5 * vanish
            let path = CGMutablePath()
            path.move(to: CGPoint(
                x: centre.x + CGFloat(cos(angle)) * inner,
                y: centre.y + CGFloat(sin(angle)) * inner * 0.2
            ))
            path.addLine(to: CGPoint(
                x: centre.x + CGFloat(cos(angle)) * outer,
                y: centre.y + CGFloat(sin(angle)) * outer * 0.2
            ))
            stroke(
                context,
                path: path,
                color: palette.fur.copy(alpha: intensity * 0.9) ?? palette.fur,
                width: 2.6 - 1.2 * vanish
            )
        }
    }

    private func drawTail(in context: CGContext, pose: CatPose, anatomy: CatAnatomy) {
        let traits = pose.species.traits
        let sway = sin(pose.tailPhase) * 0.40 * anatomy.tailSway
        let lift = cos(pose.tailPhase * 0.7) * 3.0 * anatomy.tailSway

        context.saveGState()
        // Pivot inside the body, so the visible tail swings from the rump
        // rather than detaching from it. A curled tail is the same curve, tipped
        // up over her back.
        let curl: Double = traits.tail == .curl ? -0.5 : 0
        context.translateBy(x: anatomy.tailBase.x, y: anatomy.tailBase.y)
        context.rotate(by: sway + curl)
        context.translateBy(x: -anatomy.tailBase.x, y: -anatomy.tailBase.y)

        switch traits.tail {
        case .puff:
            // A ball of fluff: three overlapping circles, which is a cotton tail
            // for the price of three ellipses. The sway becomes a bounce.
            let bounce = CGFloat(lift) * 0.4
            let radius = max(4, anatomy.tailWidth * 0.55)
            let centre = CGPoint(
                x: anatomy.tailBase.x - radius * 1.05,
                y: anatomy.tailBase.y + radius * 0.5 + bounce
            )
            for (offset, size) in [
                (CGPoint(x: 0, y: 0), radius),
                (CGPoint(x: -radius * 0.75, y: radius * 0.45), radius * 0.72),
                (CGPoint(x: radius * 0.3, y: radius * 0.7), radius * 0.6),
            ] {
                let rect = CGRect(
                    x: centre.x + offset.x - size,
                    y: centre.y + offset.y - size,
                    width: size * 2,
                    height: size * 2
                )
                fillStroke(
                    context,
                    path: CGPath(ellipseIn: rect, transform: nil),
                    fill: palette.fur,
                    stroke: palette.outline,
                    width: outlineWidth * 0.8
                )
            }
            context.setFillColor(palette.belly)
            context.fillEllipse(in: CGRect(
                x: centre.x - radius * 0.55,
                y: centre.y - radius * 0.15,
                width: radius * 0.75,
                height: radius * 0.7
            ))

        case .brush:
            // The spine, then the fluff: a brush is a shape with a tail curve
            // through it rather than a tail drawn with a wide pen.
            let tip = CGPoint(x: anatomy.tailTip.x, y: anatomy.tailTip.y + lift)
            let mid = CGPoint(
                x: (anatomy.tailBase.x + anatomy.tailControl1.x + anatomy.tailControl2.x + tip.x) / 4,
                y: (anatomy.tailBase.y + anatomy.tailControl1.y + anatomy.tailControl2.y + tip.y) / 4
            )
            let spine = CGMutablePath()
            spine.move(to: anatomy.tailBase)
            spine.addCurve(
                to: tip,
                control1: anatomy.tailControl1,
                control2: CGPoint(x: anatomy.tailControl2.x, y: anatomy.tailControl2.y + lift)
            )
            stroke(context, path: spine, color: palette.outline, width: anatomy.tailOutlineWidth)
            stroke(context, path: spine, color: palette.fur, width: anatomy.tailFurWidth)

            // Elongated *along* the spine so the fluff hugs the tail: a round
            // blob in the middle reads as a balloon on a string.
            let fluff = anatomy.tailFurWidth * 1.05
            context.saveGState()
            context.translateBy(x: mid.x, y: mid.y)
            context.rotate(by: atan2(tip.y - anatomy.tailBase.y, tip.x - anatomy.tailBase.x))
            fillStroke(
                context,
                path: CGPath(ellipseIn: CGRect(
                    x: -fluff * 0.55,
                    y: -fluff * 1.1,
                    width: fluff * 1.1,
                    height: fluff * 2.2
                ), transform: nil),
                fill: palette.fur,
                stroke: palette.outline,
                width: outlineWidth * 0.8
            )
            context.restoreGState()

            // The pale end, overlapping the fluff rather than floating past it.
            let tipRadius = anatomy.tailFurWidth * 0.68
            fillStroke(
                context,
                path: CGPath(ellipseIn: CGRect(
                    x: tip.x - tipRadius,
                    y: tip.y - tipRadius,
                    width: tipRadius * 2,
                    height: tipRadius * 2
                ), transform: nil),
                fill: palette.belly,
                stroke: palette.outline,
                width: outlineWidth * 0.7
            )

        case .curve, .curl:
            // A curl is the same curve, tipped up over her back by `curl` above.
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

            // The brush tip: a lighter end, which is half of what makes a fox
            // read as a fox.
            if traits.tailTuft {
                let tip = CGPoint(x: anatomy.tailTip.x, y: anatomy.tailTip.y + lift)
                let radius = anatomy.tailFurWidth * 0.45
                fillStroke(
                    context,
                    path: CGPath(ellipseIn: CGRect(
                        x: tip.x - radius,
                        y: tip.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    ), transform: nil),
                    fill: palette.belly,
                    stroke: palette.outline,
                    width: outlineWidth * 0.7
                )
            }
        }
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
        // Markings belong to the cats and the foxes; a bunny, a puppy and a
        // panda wear plain fur, and skip the whole pass.
        if pose.species.traits.stripes {
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
    }

    /// Front paws. In the tucked shapes they land on top of the body silhouette
    /// and read as paws folded under the chest, which is what a loaf looks like
    /// from the front.
    private func drawPaws(in context: CGContext, pose: CatPose, anatomy: CatAnatomy) {
        let traits = pose.species.traits
        // A panda's limbs are the dark half of its coat, and a fox's feet are
        // dark socks: both take the flank colour instead of the belly.
        let fill = (traits.darkLimbs || traits.socks) ? palette.furDark : palette.belly

        for direction in [CGFloat(-1), CGFloat(1)] {
            let center = CGPoint(
                x: anatomy.bodyCenter.x + direction * anatomy.pawOffsetX,
                y: anatomy.pawCenterY
            )
            switch traits.legs {
            case .paws:
                let rect = CGRect(
                    x: center.x - anatomy.pawRadii.width,
                    y: center.y - anatomy.pawRadii.height,
                    width: anatomy.pawRadii.width * 2,
                    height: anatomy.pawRadii.height * 2
                )
                fillStroke(
                    context,
                    path: CGPath(ellipseIn: rect, transform: nil),
                    fill: fill,
                    stroke: palette.outline,
                    width: outlineWidth * 0.85
                )
            case .short:
                // Very short legs: the paw sits closer to the body, so a corgi or
                // a frog reads as low to the ground rather than as a small cat.
                let rect = CGRect(
                    x: center.x - anatomy.pawRadii.width * 1.05,
                    y: center.y - anatomy.pawRadii.height * 0.7,
                    width: anatomy.pawRadii.width * 2.1,
                    height: anatomy.pawRadii.height * 1.4
                )
                fillStroke(
                    context,
                    path: CGPath(ellipseIn: rect, transform: nil),
                    fill: fill,
                    stroke: palette.outline,
                    width: outlineWidth * 0.8
                )
            case .webbed:
                // Flat and splayed, in the bill's colour: the whole reason a
                // duckling reads as a duckling from the feet up.
                let rect = CGRect(
                    x: center.x - anatomy.pawRadii.width * 1.35,
                    y: center.y - anatomy.pawRadii.height * 0.8,
                    width: anatomy.pawRadii.width * 2.7,
                    height: anatomy.pawRadii.height * 1.6
                )
                fillStroke(
                    context,
                    path: CGPath(ellipseIn: rect, transform: nil),
                    fill: palette.nose,
                    stroke: palette.outline,
                    width: outlineWidth * 0.8
                )
                // Two notches, so the foot reads as webbed rather than as a blob.
                for step in [CGFloat(-0.45), CGFloat(0.45)] {
                    let notch = CGMutablePath()
                    let x = center.x + step * anatomy.pawRadii.width
                    notch.move(to: CGPoint(x: x, y: rect.maxY))
                    notch.addLine(to: CGPoint(x: x, y: rect.minY + rect.height * 0.35))
                    stroke(context, path: notch, color: palette.outline, width: outlineWidth * 0.5)
                }
            }
        }
    }

    /// A foreleg thrown at somebody, and the comic hit where it lands.
    ///
    /// The paw is drawn out in front of the shoulder and the burst just beyond
    /// it, on the side she is facing — so a brawl reads as two animals swinging
    /// at each other even at this size, where a lean and a hop on their own read
    /// as a stumble.
    private func drawPunch(in context: CGContext, pose: CatPose, anatomy: CatAnatomy) {
        let punch = CGFloat(max(-1, min(1, pose.punch)))
        let amount = abs(punch)
        guard amount > 0.05 else { return }
        let near = punch >= 0 ? CGFloat(1) : CGFloat(-1)

        let shoulder = CGPoint(
            x: anatomy.bodyCenter.x + near * anatomy.bodyRadii.width * 0.55,
            y: anatomy.bodyCenter.y + anatomy.bodyRadii.height * 0.5
        )
        // Short enough to leave the art envelope some margin: at the first
        // length the swing ended exactly on the stage edge, which the transient
        // sweep failed on and which any wider animal would have overflowed.
        // Capped, because a punch is an *arm*: a bear's belly is wider than a
        // hamster's, and letting the swing grow with it put a bear's paw on the
        // edge of the stage.
        // Long enough to reach a face at the distance a brawl holds them, and
        // aimed *up*: a punch at chest height is a shove.
        let armLength = min(anatomy.bodyRadii.width * 0.42, 12)
        let reach = (armLength + anatomy.pawRadii.width * 1.5) * amount
        let paw = CGPoint(
            x: shoulder.x + near * reach * 0.85,
            y: shoulder.y + reach * 0.85
        )

        // The arm, then the paw on the end of it.
        let arm = CGMutablePath()
        arm.move(to: shoulder)
        arm.addQuadCurve(
            to: paw,
            control: CGPoint(x: shoulder.x + near * reach * 0.35, y: shoulder.y + reach * 0.75)
        )
        stroke(context, path: arm, color: palette.outline, width: anatomy.pawRadii.width * 1.5)
        stroke(context, path: arm, color: palette.fur, width: anatomy.pawRadii.width * 1.5 - outlineWidth)
        fillStroke(
            context,
            path: CGPath(ellipseIn: CGRect(
                x: paw.x - anatomy.pawRadii.width * 0.85,
                y: paw.y - anatomy.pawRadii.width * 0.85,
                width: anatomy.pawRadii.width * 1.7,
                height: anatomy.pawRadii.width * 1.7
            ), transform: nil),
            fill: palette.belly,
            stroke: palette.outline,
            width: outlineWidth * 0.8
        )

    }

    /// The colour a marking is drawn in, chosen for contrast against the fur.
    ///
    /// Both ends are fur tones rather than accents: `furDark` or the outline for a
    /// dark marking, `belly` or `furDark` for a pale one. Picking the *most*
    /// contrasting palette colour instead produced a blue heart on a white bunny
    /// and a pink sock on a black cat — high contrast, and nothing like fur.
    private func markingColour(light: Bool) -> CGColor {
        let candidates: [CGColor] = light
            ? [palette.belly, palette.furDark]
            : [palette.furDark, palette.outline]
        let fur = luminance(palette.fur)
        return candidates.max { abs(luminance($0) - fur) < abs(luminance($1) - fur) } ?? palette.furDark
    }

    private func luminance(_ colour: CGColor) -> Double {
        guard let components = colour.components, components.count >= 3 else { return 0 }
        return 0.2126 * Double(components[0])
            + 0.7152 * Double(components[1])
            + 0.0722 * Double(components[2])
    }

    /// Markings, drawn over whatever the coat and species already put down.
    ///
    /// Two rules make eight markings work on fourteen coats and eight species.
    /// Every one is drawn from fur tones chosen for contrast (see
    /// `markingColour`), and every one is *outlined* — which is the same rule the
    /// rest of this art follows, and the only thing that keeps a pale marking
    /// visible on a pale pookie.
    private func drawPattern(in context: CGContext, pose: CatPose, anatomy: CatAnatomy) {
        // A species can own a marking: a raccoon's tail is ringed whether or not
        // the human picked anything.
        if pose.species.traits.ringedTail {
            drawTailRings(
                in: context,
                anatomy: anatomy,
                colour: markingColour(light: false),
                width: outlineWidth * 1.1
            )
        }

        let pattern = pose.pattern
        guard pattern != .plain else { return }
        // The two markings that live on the head are drawn separately, between the
        // head and the face: drawn with the body they end up *under* the skull,
        // which is how the first version of the eye patch and the mask were
        // invisible on every pookie.
        guard pattern != .eyePatch, pattern != .mask else { return }

        let dark = markingColour(light: false)
        let pale = markingColour(light: true)
        let headScale = anatomy.headScale
        let body = anatomy.bodyCenter
        let radii = anatomy.bodyRadii
        let hairline = outlineWidth * 0.7

        func bodyClip() -> CGPath {
            CGPath(ellipseIn: CGRect(
                x: body.x - radii.width,
                y: body.y - radii.height,
                width: radii.width * 2,
                height: radii.height * 2
            ), transform: nil)
        }

        switch pattern {
        case .plain:
            break

        case .eyePatch, .mask:
            // On the head: drawn by `drawFacePattern`, between the skull and the
            // face.
            break

        case .sock:
            // One paw, on the side she is facing, so it is the one you see.
            let centre = CGPoint(
                x: body.x + CGFloat(pose.facing) * anatomy.pawOffsetX,
                y: anatomy.pawCenterY
            )
            // A whole leg, not a spot on the foot: at this size a pale dot on a
            // paw is indistinguishable from the paw.
            let rect = CGRect(
                x: centre.x - anatomy.pawRadii.width * 1.3,
                y: centre.y - anatomy.pawRadii.height,
                width: anatomy.pawRadii.width * 2.6,
                height: anatomy.pawRadii.height * 5.2
            )
            fillStroke(
                context,
                path: CGPath(ellipseIn: rect, transform: nil),
                fill: pale,
                stroke: palette.outline,
                width: hairline
            )

        case .heart:
            // Two lobes and a point, low on the flank so the muzzle does not sit
            // on top of it.
            let size = radii.width * 0.5
            let centre = CGPoint(x: body.x + radii.width * 0.1, y: body.y - radii.height * 0.28)
            let heart = CGMutablePath()
            heart.move(to: CGPoint(x: centre.x, y: centre.y - size * 0.9))
            heart.addQuadCurve(
                to: CGPoint(x: centre.x - size, y: centre.y + size * 0.4),
                control: CGPoint(x: centre.x - size * 1.4, y: centre.y - size * 0.7)
            )
            heart.addQuadCurve(
                to: CGPoint(x: centre.x, y: centre.y + size * 0.95),
                control: CGPoint(x: centre.x - size * 0.5, y: centre.y + size * 0.95)
            )
            heart.addQuadCurve(
                to: CGPoint(x: centre.x + size, y: centre.y + size * 0.4),
                control: CGPoint(x: centre.x + size * 0.5, y: centre.y + size * 0.95)
            )
            heart.addQuadCurve(
                to: CGPoint(x: centre.x, y: centre.y - size * 0.9),
                control: CGPoint(x: centre.x + size * 1.4, y: centre.y - size * 0.7)
            )
            heart.closeSubpath()
            fillStroke(context, path: heart, fill: dark, stroke: palette.outline, width: hairline)

        case .ringTail:
            drawTailRings(in: context, anatomy: anatomy, colour: dark, width: hairline * 1.6)

        case .rosettes:
            // Three rings on the flank, low, clipped to the body.
            context.saveGState()
            context.addPath(bodyClip())
            context.clip()
            for (dx, dy, size) in [
                (CGFloat(-0.5), CGFloat(0.2), CGFloat(0.36)),
                (CGFloat(0.35), CGFloat(-0.15), CGFloat(0.4)),
                (CGFloat(-0.05), CGFloat(-0.62), CGFloat(0.3)),
            ] {
                let radius = radii.width * size
                let centre = CGPoint(x: body.x + radii.width * dx, y: body.y + radii.height * dy)
                let ring = CGMutablePath()
                ring.addEllipse(in: CGRect(
                    x: centre.x - radius,
                    y: centre.y - radius * 0.8,
                    width: radius * 2,
                    height: radius * 1.6
                ))
                stroke(context, path: ring, color: dark, width: hairline * 1.5)
            }
            context.restoreGState()

        case .stars:
            // Four-pointed, because a five-pointed star six points across is a
            // smudge.
            context.saveGState()
            context.addPath(bodyClip())
            context.clip()
            for (dx, dy, size) in [
                (CGFloat(-0.55), CGFloat(0.3), CGFloat(5.4)),
                (CGFloat(0.15), CGFloat(-0.35), CGFloat(4.4)),
                (CGFloat(0.5), CGFloat(0.35), CGFloat(3.8)),
                (CGFloat(-0.2), CGFloat(-0.65), CGFloat(3.4)),
                (CGFloat(0.45), CGFloat(-0.7), CGFloat(3.0)),
            ] {
                let centre = CGPoint(x: body.x + radii.width * dx, y: body.y + radii.height * dy)
                let reach = size * headScale
                let star = CGMutablePath()
                star.move(to: CGPoint(x: centre.x, y: centre.y + reach))
                star.addQuadCurve(
                    to: CGPoint(x: centre.x + reach, y: centre.y),
                    control: CGPoint(x: centre.x + reach * 0.16, y: centre.y + reach * 0.16)
                )
                star.addQuadCurve(
                    to: CGPoint(x: centre.x, y: centre.y - reach),
                    control: CGPoint(x: centre.x + reach * 0.16, y: centre.y - reach * 0.16)
                )
                star.addQuadCurve(
                    to: CGPoint(x: centre.x - reach, y: centre.y),
                    control: CGPoint(x: centre.x - reach * 0.16, y: centre.y - reach * 0.16)
                )
                star.addQuadCurve(
                    to: CGPoint(x: centre.x, y: centre.y + reach),
                    control: CGPoint(x: centre.x - reach * 0.16, y: centre.y + reach * 0.16)
                )
                star.closeSubpath()
                fillStroke(context, path: star, fill: pale, stroke: palette.outline, width: hairline * 0.7)
            }
            context.restoreGState()

        case .frost:
            // A winter coat: pale muzzle, chest and paws, outlined like everything
            // else so it shows on a pale pookie too.
            let chest = CGRect(
                x: body.x - radii.width * 0.62,
                y: body.y - radii.height * 0.72,
                width: radii.width * 1.24,
                height: radii.height * 1.45
            )
            fillStroke(
                context,
                path: CGPath(ellipseIn: chest, transform: nil),
                fill: pale,
                stroke: palette.outline,
                width: hairline
            )
            let muzzle = CGRect(
                x: anatomy.muzzleCenter.x - anatomy.muzzleRadii.width * 1.15,
                y: anatomy.muzzleCenter.y - anatomy.muzzleRadii.height * 1.05,
                width: anatomy.muzzleRadii.width * 2.3,
                height: anatomy.muzzleRadii.height * 2.1
            )
            fillStroke(
                context,
                path: CGPath(ellipseIn: muzzle, transform: nil),
                fill: pale,
                stroke: palette.outline,
                width: hairline
            )
            for direction in [CGFloat(-1), CGFloat(1)] {
                let centre = CGPoint(
                    x: body.x + direction * anatomy.pawOffsetX,
                    y: anatomy.pawCenterY
                )
                fillStroke(
                    context,
                    path: CGPath(ellipseIn: CGRect(
                        x: centre.x - anatomy.pawRadii.width,
                        y: centre.y - anatomy.pawRadii.height,
                        width: anatomy.pawRadii.width * 2,
                        height: anatomy.pawRadii.height * 2
                    ), transform: nil),
                    fill: pale,
                    stroke: palette.outline,
                    width: hairline
                )
            }
        }
    }

    /// The markings that sit on the head, drawn after the skull and before the
    /// face, so a patch is over the fur and under the eye.
    private func drawFacePattern(in context: CGContext, pose: CatPose, anatomy: CatAnatomy) {
        let pattern = pose.pattern
        guard pattern == .eyePatch || pattern == .mask else { return }
        let dark = markingColour(light: false)
        let hairline = outlineWidth * 0.7

        switch pattern {
        case .eyePatch:
            // One eye, not two: an eye patch is a marking, the panda's face is a
            // species.
            let centre = CGPoint(x: anatomy.headCenter.x - anatomy.eyeOffsetX, y: anatomy.eyeY)
            context.saveGState()
            context.translateBy(x: centre.x, y: centre.y)
            context.rotate(by: -0.4)
            let patch = CGRect(
                x: -anatomy.eyeRadius * 2.6,
                y: -anatomy.eyeRadius * 2.4,
                width: anatomy.eyeRadius * 5.2,
                height: anatomy.eyeRadius * 4.8
            )
            fillStroke(
                context,
                path: CGPath(ellipseIn: patch, transform: nil),
                fill: dark,
                stroke: palette.outline,
                width: hairline
            )
            context.restoreGState()

        case .mask:
            // A band across both eyes, wide enough to reach the sides of the head
            // and outlined so it shows on a dark coat too.
            let width = anatomy.headRadius * 2.3
            let height = anatomy.eyeRadius * 3.1
            let band = CGRect(
                x: anatomy.headCenter.x - width / 2,
                y: anatomy.eyeY - height / 2,
                width: width,
                height: height
            )
            fillStroke(
                context,
                path: CGPath(ellipseIn: band, transform: nil),
                fill: dark,
                stroke: palette.outline,
                width: hairline
            )

        case .plain, .sock, .heart, .ringTail, .rosettes, .stars, .frost:
            break
        }
    }

    /// A duckling's wing, folded at rest and lifted as `flap` rises.
    ///
    /// Drawn after the body so it sits on the flank, and mirrored with the facing
    /// flip like everything else.
    private func drawWings(in context: CGContext, pose: CatPose, anatomy: CatAnatomy) {
        let traits = pose.species.traits
        guard traits.wings else { return }
        let flap = CGFloat(pose.flap)
        let scale = anatomy.headScale
        let reach = 15 * scale

        for direction in [CGFloat(-1), CGFloat(1)] {
            let anchor = CGPoint(
                x: anatomy.bodyCenter.x + direction * anatomy.bodyRadii.width * 0.55,
                y: anatomy.bodyCenter.y + anatomy.bodyRadii.height * 0.15
            )
            context.saveGState()
            context.translateBy(x: anchor.x, y: anchor.y)
            // Up and out as it flaps; a flutter is a small angle, a flight is a
            // big one.
            context.rotate(by: direction * (0.25 + 0.9 * flap))
            let wing = CGRect(
                x: -reach * 0.45,
                y: -reach * 0.35,
                width: reach * 1.5,
                height: reach * 0.95
            )
            fillStroke(
                context,
                path: CGPath(ellipseIn: wing, transform: nil),
                fill: palette.furDark,
                stroke: palette.outline,
                width: outlineWidth * 0.8
            )
            // One feather line, so the wing is not just a second body.
            let feather = CGMutablePath()
            feather.move(to: CGPoint(x: -reach * 0.2, y: 0))
            feather.addLine(to: CGPoint(x: reach * 0.75, y: 0))
            stroke(context, path: feather, color: palette.outline, width: outlineWidth * 0.5)
            context.restoreGState()
        }
    }

    /// Bars *across* the tail, not dashes along it: a dashed stroke on a tail this
    /// size merges into one dark tail. Three points off the same cubic the tail is
    /// drawn with, so the rings follow whatever shape the tail has.
    private func drawTailRings(
        in context: CGContext,
        anatomy: CatAnatomy,
        colour: CGColor,
        width: CGFloat
    ) {
        let p0 = anatomy.tailBase
        let p1 = anatomy.tailControl1
        let p2 = anatomy.tailControl2
        let p3 = anatomy.tailTip
        func along(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(
                x: u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
                y: u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y
            )
        }
        for t in [CGFloat(0.3), 0.5, 0.7] {
            let point = along(t)
            let half = anatomy.tailWidth * 0.42
            let bar = CGMutablePath()
            bar.move(to: CGPoint(x: point.x - half * 0.5, y: point.y - half))
            bar.addLine(to: CGPoint(x: point.x + half * 0.5, y: point.y + half))
            stroke(context, path: bar, color: colour, width: width)
        }
    }

    /// A hedgehog's back: one row of triangles along the spine, in the dark half
    /// of the coat. Cheap, and it is the entire animal.
    private func drawSpikes(in context: CGContext, anatomy: CatAnatomy) {
        let count = 9
        let reach = anatomy.bodyRadii.height * 0.55
        for index in 0..<count {
            let t = (CGFloat(index) + 0.5) / CGFloat(count)
            let angle = CGFloat.pi * (0.15 + 0.7 * t)
            let base = CGPoint(
                x: anatomy.bodyCenter.x - cos(angle) * anatomy.bodyRadii.width * 0.95,
                y: anatomy.bodyCenter.y + sin(angle) * anatomy.bodyRadii.height * 0.95
            )
            let spike = CGMutablePath()
            spike.move(to: CGPoint(x: base.x - reach * 0.22, y: base.y - reach * 0.12))
            spike.addLine(to: CGPoint(
                x: base.x - cos(angle) * reach,
                y: base.y + sin(angle) * reach
            ))
            spike.addLine(to: CGPoint(x: base.x + reach * 0.22, y: base.y + reach * 0.12))
            spike.closeSubpath()
            fillStroke(
                context,
                path: spike,
                fill: palette.furDark,
                stroke: palette.outline,
                width: outlineWidth * 0.6
            )
        }
    }

    /// An axolotl's gills: three frills a side, off the back of the head.
    private func drawGills(in context: CGContext, pose: CatPose, anatomy: CatAnatomy) {
        let frill = palette.earInner
        for direction in [CGFloat(-1), CGFloat(1)] {
            for index in 0..<3 {
                let step = CGFloat(index) - 1
                let base = CGPoint(
                    x: anatomy.headCenter.x + direction * anatomy.headRadius * 0.9,
                    y: anatomy.headCenter.y + anatomy.headRadius * (0.42 + step * 0.42)
                )
                context.saveGState()
                context.translateBy(x: base.x, y: base.y)
                context.rotate(by: direction * (0.5 + step * 0.32))
                let frond = CGRect(
                    x: 0,
                    y: -anatomy.headRadius * 0.12,
                    width: anatomy.headRadius * 0.85,
                    height: anatomy.headRadius * 0.24
                )
                fillStroke(
                    context,
                    path: CGPath(ellipseIn: frond, transform: nil),
                    fill: frill,
                    stroke: palette.outline,
                    width: outlineWidth * 0.55
                )
                context.restoreGState()
            }
        }
    }

    /// A pale ruff at the jaw, which is how a fox is told from a cat at a glance.
    private func drawCheekRuff(in context: CGContext, anatomy: CatAnatomy) {
        for direction in [CGFloat(-1), CGFloat(1)] {
            let centre = CGPoint(
                x: anatomy.headCenter.x + direction * anatomy.headRadius * 0.72,
                y: anatomy.headCenter.y - anatomy.headRadius * 0.34
            )
            let rect = CGRect(
                x: centre.x - anatomy.headRadius * 0.42,
                y: centre.y - anatomy.headRadius * 0.3,
                width: anatomy.headRadius * 0.84,
                height: anatomy.headRadius * 0.6
            )
            context.setFillColor(palette.belly)
            context.fillEllipse(in: rect)
        }
    }

    /// A hamster's cheeks: two puffs either side of the muzzle, which is the
    /// whole joke of a hamster.
    private func drawCheeks(in context: CGContext, anatomy: CatAnatomy) {
        for direction in [CGFloat(-1), CGFloat(1)] {
            let centre = CGPoint(
                x: anatomy.headCenter.x + direction * anatomy.headRadius * 0.78,
                y: anatomy.headCenter.y - anatomy.headRadius * 0.3
            )
            let radius = anatomy.headRadius * 0.42
            fillStroke(
                context,
                path: CGPath(ellipseIn: CGRect(
                    x: centre.x - radius,
                    y: centre.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ), transform: nil),
                fill: palette.belly,
                stroke: palette.outline,
                width: outlineWidth * 0.6
            )
        }
    }

    /// Ears are drawn *before* the head, so their bases tuck behind the skull.
    /// That overlap is what makes them read as attached rather than stuck on.
    ///
    /// Four shapes cover the five species. A tall-eared animal is smaller overall
    /// (`SpeciesTraits.scale`), which is what keeps a bunny's ears inside the
    /// same stage the cat defined — the alternative was a taller window for every
    /// pet, and a taller window is a longer ledge she no longer fits on.
    private func drawEars(in context: CGContext, pose: CatPose, anatomy: CatAnatomy) {
        let traits = pose.species.traits
        let scale = anatomy.headScale
        let twitch = CGFloat(pose.earTwitch)
        let flattened = pose.mood == .dragged || pose.mood == .alarmed
        let lift = traits.earLift * (flattened ? 0.63 : 1)
        let outerFill = traits.darkLimbs ? palette.furDark : palette.fur

        for direction in [CGFloat(-1), CGFloat(1)] {
            let pivot = CGPoint(
                x: anatomy.headCenter.x + direction * 16 * scale,
                y: anatomy.headCenter.y + 12 * scale
            )
            context.saveGState()
            context.translateBy(x: pivot.x, y: pivot.y)
            context.rotate(by: direction * twitch)
            context.translateBy(x: -pivot.x, y: -pivot.y)

            switch traits.ears {
            case .none:
                break
            case .cat:
                let tip = 19 * scale * lift
                let outer = CGMutablePath()
                outer.move(to: CGPoint(x: pivot.x + direction * 10 * scale, y: pivot.y - 10 * scale))
                outer.addLine(to: CGPoint(x: pivot.x - direction * 1.5 * scale, y: pivot.y + tip))
                outer.addLine(to: CGPoint(x: pivot.x - direction * 8 * scale, y: pivot.y + 8 * scale))
                outer.closeSubpath()
                fillStroke(context, path: outer, fill: outerFill, stroke: palette.outline, width: outlineWidth)

                let inner = CGMutablePath()
                inner.move(to: CGPoint(x: pivot.x + direction * 5.5 * scale, y: pivot.y - 5.5 * scale))
                inner.addLine(to: CGPoint(x: pivot.x - direction * 1.5 * scale, y: pivot.y + tip - 7 * scale))
                inner.addLine(to: CGPoint(x: pivot.x - direction * 4.5 * scale, y: pivot.y + 4.5 * scale))
                inner.closeSubpath()
                context.setFillColor(palette.earInner)
                context.addPath(inner)
                context.fillPath()

            case .pointed:
                // Taller, wider set and with a dark tip; and a fox's ears are
                // pale inside where a cat's are pink, which is one of the few
                // things that tells the two apart at this size.
                let innerFill = traits.paleEarInner ? palette.belly : palette.earInner
                let tip = 24 * scale * lift
                let outer = CGMutablePath()
                outer.move(to: CGPoint(x: pivot.x + direction * 11 * scale, y: pivot.y - 11 * scale))
                outer.addLine(to: CGPoint(x: pivot.x - direction * 2.5 * scale, y: pivot.y + tip))
                outer.addLine(to: CGPoint(x: pivot.x - direction * 9.5 * scale, y: pivot.y + 7 * scale))
                outer.closeSubpath()
                fillStroke(context, path: outer, fill: outerFill, stroke: palette.outline, width: outlineWidth)

                let inner = CGMutablePath()
                inner.move(to: CGPoint(x: pivot.x + direction * 6 * scale, y: pivot.y - 5 * scale))
                inner.addLine(to: CGPoint(x: pivot.x - direction * 2 * scale, y: pivot.y + tip - 6 * scale))
                inner.addLine(to: CGPoint(x: pivot.x - direction * 5 * scale, y: pivot.y + 3 * scale))
                inner.closeSubpath()
                context.setFillColor(innerFill)
                context.addPath(inner)
                context.fillPath()

                let tipPatch = CGMutablePath()
                tipPatch.move(to: CGPoint(x: pivot.x - direction * 1.4 * scale, y: pivot.y + tip - 9 * scale))
                tipPatch.addLine(to: CGPoint(x: pivot.x - direction * 2.5 * scale, y: pivot.y + tip))
                tipPatch.addLine(to: CGPoint(x: pivot.x - direction * 5 * scale, y: pivot.y + tip - 8 * scale))
                tipPatch.closeSubpath()
                context.setFillColor(palette.furDark)
                context.addPath(tipPatch)
                context.fillPath()

            case .long:
                // A tall standing oval, tipped outward. This is the ear that sets
                // the bunny's whole silhouette.
                let length = 34 * scale * lift
                context.saveGState()
                context.translateBy(x: pivot.x, y: pivot.y)
                context.rotate(by: direction * 0.16)
                let outer = CGRect(
                    x: -4.6 * scale,
                    y: 2 * scale,
                    width: 9.2 * scale,
                    height: length
                )
                fillStroke(
                    context,
                    path: CGPath(ellipseIn: outer, transform: nil),
                    fill: outerFill,
                    stroke: palette.outline,
                    width: outlineWidth
                )
                let inner = outer.insetBy(dx: 2.4 * scale, dy: 4 * scale)
                context.setFillColor(palette.earInner)
                context.fillEllipse(in: inner)
                context.restoreGState()

            case .floppy:
                // A rounded flap hanging off the side of the head rather than
                // standing above it: softer, and free of height.
                context.saveGState()
                context.translateBy(x: pivot.x + direction * 4 * scale, y: pivot.y - 14 * scale)
                context.rotate(by: direction * 0.34)
                let flap = CGRect(x: -7 * scale, y: -15 * scale, width: 14 * scale, height: 30 * scale)
                fillStroke(
                    context,
                    path: CGPath(ellipseIn: flap, transform: nil),
                    fill: outerFill,
                    stroke: palette.outline,
                    width: outlineWidth
                )
                context.setFillColor(palette.earInner)
                context.fillEllipse(in: flap.insetBy(dx: 3 * scale, dy: 5 * scale))
                context.restoreGState()

            case .round:
                // A button on top of the head — panda, bear, anything round.
                let button = CGRect(
                    x: pivot.x - 9 * scale,
                    y: pivot.y + 1 * scale,
                    width: 18 * scale,
                    height: 18 * scale
                )
                fillStroke(
                    context,
                    path: CGPath(ellipseIn: button, transform: nil),
                    fill: outerFill,
                    stroke: palette.outline,
                    width: outlineWidth
                )
                context.setFillColor(palette.earInner)
                context.fillEllipse(in: button.insetBy(dx: 3.5 * scale, dy: 3.5 * scale))
            }

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

    /// A duckling's bill, in place of a muzzle and nose.
    private func drawBill(in context: CGContext, pose: CatPose, anatomy: CatAnatomy) {
        let open = CGFloat(pose.mouthOpen) * 0.5
        let width = anatomy.muzzleRadii.width * 1.5
        let height = anatomy.muzzleRadii.height * 0.85
        let centre = CGPoint(x: anatomy.muzzleCenter.x, y: anatomy.muzzleCenter.y)

        // Lower mandible first, so an open bill shows a dark gap.
        for (offset, fill) in [(CGFloat(-height * 0.55), palette.nose), (height * 0.25 + open * 4, palette.nose)] {
            let rect = CGRect(
                x: centre.x - width,
                y: centre.y + offset - height * 0.45,
                width: width * 2,
                height: height * 0.9
            )
            fillStroke(
                context,
                path: CGPath(ellipseIn: rect, transform: nil),
                fill: fill,
                stroke: palette.outline,
                width: outlineWidth * 0.7
            )
        }
        // The nostrils, which is what stops it reading as a second nose.
        for direction in [CGFloat(-1), CGFloat(1)] {
            let dot = CGMutablePath()
            dot.addEllipse(in: CGRect(
                x: centre.x + direction * width * 0.35 - 0.8,
                y: centre.y + height * 0.3,
                width: 1.6,
                height: 1.6
            ))
            context.setFillColor(palette.outline)
            context.addPath(dot)
            context.fillPath()
        }
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

        // A panda is read entirely from its patches, so they go down before the
        // eyes and are simply a pair of dark ellipses around them.
        if pose.species.traits.eyePatches {
            for direction in [CGFloat(-1), CGFloat(1)] {
                let centre = CGPoint(
                    x: anatomy.headCenter.x + direction * anatomy.eyeOffsetX,
                    y: anatomy.eyeY
                )
                context.saveGState()
                context.translateBy(x: centre.x, y: centre.y)
                context.rotate(by: direction * 0.5)
                fillStroke(
                    context,
                    path: CGPath(ellipseIn: CGRect(
                        x: -eyeRadius * 1.15,
                        y: -eyeRadius * 1.0,
                        width: eyeRadius * 2.3,
                        height: eyeRadius * 2.05
                    ), transform: nil),
                    fill: palette.furDark,
                    stroke: palette.outline,
                    width: outlineWidth * 0.7
                )
                context.restoreGState()
            }
        }

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

        // A bird has a bill instead of the whole muzzle-nose-mouth assembly, and
        // it is drawn in the bill's own colour rather than the belly.
        if pose.species.traits.bill {
            drawBill(in: context, pose: pose, anatomy: anatomy)
            return
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
        fillStroke(context, path: nose, fill: palette.nose, stroke: palette.outline, width: 1.6 * anatomy.muzzleScale)

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
            fillStroke(context, path: openPath, fill: palette.mouth, stroke: palette.outline, width: 1.6 * anatomy.muzzleScale)
            // Tongue, because it is funny.
            if mouthOpen > 0.45 {
                let tongue = CGRect(
                    x: muzzle.x - muzzleRadii.width * (3.0 / 11),
                    y: muzzle.y - muzzleRadii.height * (11.5 / 7.5),
                    width: muzzleRadii.width * (6.0 / 11),
                    height: muzzleRadii.height * (3.4 / 7.5)
                )
                context.setFillColor(palette.tongue)
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

        // Whiskers. A cat's and a fox's; a bunny, a puppy and a panda have
        // muzzles without them, and the face reads cleaner for the omission.
        let whiskerWidth = 1.3 * anatomy.muzzleScale
        for direction in [CGFloat(-1), CGFloat(1)] where pose.species.traits.whiskers {
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
            context.setFillColor(palette.blush.copy(alpha: 0.45 * blush) ?? palette.blush)
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

    private func drawHeadStripes(in context: CGContext, pose: CatPose, anatomy: CatAnatomy) {
        guard pose.species.traits.stripes else { return }
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
