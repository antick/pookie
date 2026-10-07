import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Headless checks and offscreen renders.
///
/// These exist because "it looked fine when I ran it" is not evidence. The
/// selftest pins the bitmap-layout assumption that hit-testing depends on,
/// proves the cat cannot lose an ear or a tail to the window edge, and runs the
/// physics on a two-display topology. The PNG render produces a reviewable image
/// of the cat without needing Screen Recording permission.
enum Diagnostics {
    // MARK: - Selftest

    static func runSelfTest() -> Int32 {
        var failures: [String] = []

        func check(_ condition: Bool, _ description: String) {
            if condition {
                print("  ok   \(description)")
            } else {
                print("  FAIL \(description)")
                failures.append(description)
            }
        }

        print("Pookie selftest")
        print("")

        print("bitmap layout probe")
        let rowZeroIsBottom = MaskRaster.rowZeroIsBottom
        print("  row 0 of the CGBitmapContext buffer maps to the \(rowZeroIsBottom ? "BOTTOM" : "TOP") of the CG coordinate space")
        // Whatever the answer, a correctly-indexed mask must agree with a
        // hand-built reference: fill the bottom half, read it back via AlphaMask.
        let probeMask = makeHalfFilledMask(width: 8, height: 8)
        check(probeMask.isOpaque(at: CGPoint(x: 4, y: 1)), "mask reports bottom-half pixel as covered")
        check(!probeMask.isOpaque(at: CGPoint(x: 4, y: 6)), "mask reports top-half pixel as empty")
        check(!probeMask.isOpaque(at: CGPoint(x: -1, y: 4)), "out-of-bounds lookups are safe")

        let size = CatGeometry.preferredWindowSize
        let renderer = CatRenderer(palette: .tabby)

        print("")
        print("art envelope (the head and tail must never be cut off)")
        let stage = CatGeometry.stage
        // Every species is drawn on the same stage, so every species has to fit
        // it — the bunny's ears are what that rule is for, and they are the
        // reason an animal with long ears is scaled down instead of given a
        // taller window (a taller window is a longer ledge she no longer fits).
        for species in PetSpecies.allCases {
            let inkByShape = Dictionary(uniqueKeysWithValues: CatShape.allCases.map {
                ($0, inkPoints(renderer: renderer, shape: $0, species: species))
            })
            var shapeEnvelopes: [CatShape: CGRect] = [:]
            for shape in CatShape.allCases {
                shapeEnvelopes[shape] = transformEnvelope(
                    shape: shape,
                    points: inkByShape[shape] ?? [],
                    species: species
                )
            }
            let envelope = shapeEnvelopes.values.reduce(CGRect.null) { $0.union($1) }
            let blink = CatShape.allCases.reduce(CGRect.null) { union, shape in
                union.union(blinkEnvelope(shape: shape, points: inkByShape[shape] ?? [], species: species))
            }
            let ink = bounds(of: CatShape.allCases.flatMap { inkByShape[$0] ?? [] })
            print(String(
                format: "  info %-6@ ink x[%6.1f, %6.1f] y[%6.1f, %6.1f]  envelope x[%6.1f, %6.1f] y[%6.1f, %6.1f]",
                species.name as NSString,
                ink.minX, ink.maxX, ink.minY, ink.maxY,
                envelope.minX, envelope.maxX, envelope.minY, envelope.maxY
            ))
            if !stage.contains(envelope) || !stage.contains(blink) {
                // Say which part is out, rather than making the next person
                // bisect a rectangle by hand.
                for shape in CatShape.allCases {
                    let shapeInk = bounds(of: inkByShape[shape] ?? [])
                    print(String(
                        format: "         %-7@ ink x[%6.1f, %6.1f] y[%6.1f, %6.1f]",
                        shape.rawValue as NSString,
                        shapeInk.minX, shapeInk.maxX, shapeInk.minY, shapeInk.maxY
                    ))
                }
            }
            check(stage.contains(envelope), "\(species.name): the stage contains the worst-case pose envelope")
            check(stage.contains(blink), "\(species.name): the stage contains the blink at every step")
        }

        // The analytic envelope assumes extremes happen at parameter corners.
        // These renderings do not assume anything: they rasterise the real
        // renderer and look for ink in the window's outer ring.
        let sweep = ArtSweep.poses()
        var clippedPoses: [String] = []
        var nearestEdge: CGFloat = .greatestFiniteMagnitude
        for (index, pose) in sweep.enumerated() {
            let coverage = rasterise(renderer: renderer, size: size, pose: pose)
            let margin = edgeMargin(coverage, width: Int(size.width), height: Int(size.height))
            nearestEdge = min(nearestEdge, margin)
            if margin <= 0 {
                clippedPoses.append("pose #\(index) \(describe(pose))")
            }
        }
        print(String(format: "  info %d poses rasterised; closest ink came within %.1f px of the edge", sweep.count, nearestEdge))
        check(clippedPoses.isEmpty, "no sampled pose loses ink at the window edge\(clippedPoses.isEmpty ? "" : ": \(clippedPoses.prefix(3).joined(separator: ", "))")")

        print("")
        print("silhouette")
        guard let mask = MaskRaster.make(renderer: renderer, size: size, pose: .neutral) else {
            print("  FAIL could not rasterise the silhouette")
            return 1
        }
        let fit = CatGeometry.fit(in: size)
        print(String(format: "  info %.0fx%.0f window, design scale %.3f", size.width, size.height, fit.scale))
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            fit.viewPoint(x: x, y: y)
        }
        check(mask.isOpaque(at: point(50, 36)), "body centre is covered")
        check(mask.isOpaque(at: point(50, 66)), "head centre is covered")
        check(mask.isOpaque(at: point(38, 11)), "left paw is covered")
        check(mask.isOpaque(at: point(62, 11)), "right paw is covered")
        check(!mask.isOpaque(at: point(50, 6)), "the gap between the paws is empty")
        check(!mask.isOpaque(at: point(50, 114)), "above the ears is empty")
        check(!mask.isOpaque(at: CGPoint(x: 1, y: 1)), "the window's bottom-left corner is empty")

        let coverage = (0..<mask.height).reduce(0) { total, y in
            total + (0..<mask.width).reduce(0) { row, x in
                row + (mask.isOpaque(at: CGPoint(x: x, y: y)) ? 1 : 0)
            }
        }
        let ratio = Double(coverage) / Double(mask.width * mask.height)
        print("  info silhouette covers \(Int(ratio * 100))% of the \(mask.width)x\(mask.height) window")
        check(ratio > 0.10 && ratio < 0.60, "silhouette coverage is plausible for a bordered window")

        print("")
        print("standing on things, not above them")
        // The window's bottom edge is *not* the floor. The physics floor is
        // `motion.origin`, and the window hangs `CatGeometry.groundInset` below
        // it so the stage can hold a leaning paw and a wrapped tail. Get that
        // offset wrong and she hovers above every window top she perches on,
        // which is exactly what she used to do. This measures the real ink at
        // every size setting rather than trusting the constant.
        let standDesktop = Desktop(visibleFrames: [CGRect(x: 0, y: 0, width: 1440, height: 860)])
        for catScale in CatScale.allCases {
            let scaleSize = CGSize(
                width: (CatGeometry.preferredWindowSize.width * catScale.factor).rounded(),
                height: (CatGeometry.preferredWindowSize.height * catScale.factor).rounded()
            )
            let scaledCoverage = rasterise(renderer: renderer, size: scaleSize, pose: .neutral)
            let inkBottom = lowestInkY(
                scaledCoverage,
                width: Int(scaleSize.width),
                height: Int(scaleSize.height)
            )
            let stander = PetMotion(origin: CGPoint(x: 400, y: 200), size: scaleSize, desktop: standDesktop)
            let gap = stander.windowOrigin.y + inkBottom - stander.origin.y
            check(
                abs(gap) <= 1.0,
                "\(catScale.label): her lowest ink is on the floor line (off by \(String(format: "%.1f", gap))px)"
            )
        }

        // Growing and shrinking her keeps her feet planted and her middle put.
        let grower = PetMotion(origin: CGPoint(x: 400, y: 200), size: size, desktop: standDesktop)
        let middleBefore = grower.origin.x + grower.size.width / 2
        grower.resize(to: CGSize(width: (size.width * 1.9).rounded(), height: (size.height * 1.9).rounded()))
        check(grower.size.width > size.width, "the size setting makes her window bigger")
        check(abs(grower.origin.y - 200) < 0.01, "and leaves her feet on the same line")
        check(
            abs((grower.origin.x + grower.size.width / 2) - middleBefore) < 0.51,
            "and keeps her middle where it was rather than sliding sideways"
        )
        grower.resize(to: CGSize(width: (size.width * 0.7).rounded(), height: (size.height * 0.7).rounded()))
        check(grower.size.width < size.width, "and can make her smaller again")
        check(
            PetMotion(origin: .zero, size: size, desktop: standDesktop).windowOrigin.y
                < PetMotion(origin: .zero, size: size, desktop: standDesktop).origin.y,
            "her window hangs below the line she stands on"
        )

        print("")
        print("motion")
        let desktop = Desktop(visibleFrames: [CGRect(x: 0, y: 0, width: 1440, height: 860)])
        let motion = PetMotion(
            origin: CGPoint(x: 600, y: 400),
            size: size,
            desktop: desktop
        )
        motion.wanderEnabled = false
        motion.followCursor = false

        // A dropped pet must fall, bounce, and come to rest on the floor.
        motion.beginDrag(at: CGPoint(x: 660, y: 560))
        motion.updateDrag(to: CGPoint(x: 700, y: 620))
        motion.endDrag()

        var steps = 0
        while steps < 1200 {
            motion.advance(dt: 1.0 / 60.0)
            steps += 1
        }
        check(
            abs(motion.origin.y - desktop.visibleFrames[0].minY) < 1.0,
            "pet settles on the floor (y=\(String(format: "%.2f", motion.origin.y)))"
        )
        check(
            abs(motion.velocity.dx) < 4 && abs(motion.velocity.dy) < 4,
            "pet comes to rest (v=(\(String(format: "%.2f", motion.velocity.dx)), \(String(format: "%.2f", motion.velocity.dy))))"
        )
        check(!motion.isDragging, "pet is no longer being dragged")

        // Wandering must keep it on screen. The rest ladder is pinned out of the
        // way: a cat who sits down half way through this is not failing to
        // wander, she is doing what she is supposed to do.
        motion.wanderEnabled = true
        motion.sitAfterSeconds = 10_000
        var minX = motion.origin.x
        var maxX = motion.origin.x
        for _ in 0..<5400 {
            motion.advance(dt: 1.0 / 60.0)
            minX = min(minX, motion.origin.x)
            maxX = max(maxX, motion.origin.x)
        }
        let region = desktop.visibleFrames[0]
        check(minX >= region.minX - 0.5, "wandering never leaves the left edge (minX=\(String(format: "%.1f", minX)))")
        check(maxX <= region.maxX - size.width + 0.5, "wandering never leaves the right edge (maxX=\(String(format: "%.1f", maxX)))")
        check(maxX - minX > 300, "wandering actually travels (range=\(String(format: "%.0f", maxX - minX))pt)")

        print("")
        print("looking at the cursor")
        // The bug: the aim was computed in screen space and stored in design
        // space, which the facing flip mirrors, so a cat facing left looked
        // right. It only shows while she is facing away from the cursor — while
        // walking the other way, being carried, or with the pointer close enough
        // that she has not turned — which is why it read as "sometimes wrong".
        let leftward = PetMotion(origin: CGPoint(x: 700, y: 0), size: size, desktop: desktop)
        leftward.move(to: CGPoint(x: 200, y: 0))       // walking left, so she faces left
        leftward.cursor = CGPoint(x: 1400, y: 40)      // ...with the cursor to her right
        for _ in 0..<90 { leftward.advance(dt: 1.0 / 60.0) }
        check(leftward.facingDirection < 0, "she is walking left while the cursor is to her right")
        check(
            leftward.gazeDirectionOnScreen > 0.3,
            "and her pupils look right, at the cursor (screen gaze \(String(format: "%.2f", leftward.gazeDirectionOnScreen)))"
        )

        let rightward = PetMotion(origin: CGPoint(x: 700, y: 0), size: size, desktop: desktop)
        rightward.move(to: CGPoint(x: 1200, y: 0))     // walking right
        rightward.cursor = CGPoint(x: 40, y: 40)       // cursor to her left
        for _ in 0..<90 { rightward.advance(dt: 1.0 / 60.0) }
        check(rightward.facingDirection > 0, "she is walking right while the cursor is to her left")
        check(
            rightward.gazeDirectionOnScreen < -0.3,
            "and her pupils look left (screen gaze \(String(format: "%.2f", rightward.gazeDirectionOnScreen)))"
        )

        // And the renderer really does mirror it, which is why the conversion
        // belongs in the behaviour layer: the same design-space offset has to
        // land on opposite sides of her head depending on which way she faces.
        func pupilPosition(facing: Double) -> CGFloat? {
            var pose = CatPose()
            pose.facing = facing
            pose.gazeX = 1
            return pupilCentroidX(renderer: renderer, size: size, pose: pose)
        }
        let facingRight = pupilPosition(facing: 1)
        let facingLeft = pupilPosition(facing: -1)
        if let facingRight, let facingLeft {
            check(
                facingRight > 50 && facingLeft < 50,
                "the facing flip mirrors the pupils (\(String(format: "%.1f", facingRight)) vs \(String(format: "%.1f", facingLeft)) design units)"
            )
        } else {
            check(false, "the pupils can be found in a rendered cat")
        }

        print("")
        print("perching on other apps' windows")
        let perchDesktop = Desktop(visibleFrames: [CGRect(x: 0, y: 0, width: 1440, height: 860)])
        let perched = PetMotion(origin: CGPoint(x: 300, y: 700), size: size, desktop: perchDesktop)
        perched.wanderEnabled = false
        perched.followCursor = false
        // A window whose top edge is at y=700, on a screen whose usable top is 860.
        let window = WindowPlatform(
            windowNumber: 42,
            ownerName: "Test",
            rect: CGRect(x: 200, y: 300, width: 600, height: 400)
        )
        perched.platforms = [window]
        perched.move(to: CGPoint(x: 300, y: 702), animated: false)
        for _ in 0..<600 { perched.advance(dt: 1.0 / 60.0) }
        check(
            abs(perched.origin.y - window.top) < 1.0,
            "a thrown cat lands on the window top (y=\(String(format: "%.1f", perched.origin.y)), window top=\(Int(window.top)))"
        )
        check(perched.supportPlatform()?.windowNumber == 42, "she reports the window she is standing on")

        // Walking off the end of the perch drops her back to the desktop.
        perched.move(to: CGPoint(x: 1100, y: window.top), animated: false)
        for _ in 0..<600 { perched.advance(dt: 1.0 / 60.0) }
        check(abs(perched.origin.y) < 1.0, "she falls to the desktop after leaving the window edge")

        // One-way platforms: a window top above her head must not lift her.
        perched.move(to: CGPoint(x: 300, y: 0), animated: false)
        for _ in 0..<120 { perched.advance(dt: 1.0 / 60.0) }
        check(abs(perched.origin.y) < 1.0, "a window above her does not teleport her onto it")

        // Riding: when the window moves, so does she.
        perched.move(to: CGPoint(x: 300, y: window.top), animated: false)
        perched.platforms = [window]
        let before = perched.origin
        perched.ride(dx: 50, dy: -30)
        check(
            abs(perched.origin.x - before.x - 50) < 0.01 && abs(perched.origin.y - before.y + 30) < 0.01,
            "riding a moving window moves her by the same delta"
        )
        perched.platforms = [WindowPlatform(
            windowNumber: 42,
            ownerName: "Test",
            rect: window.rect.offsetBy(dx: 50, dy: -30)
        )]
        check(perched.supportPlatform()?.windowNumber == 42, "she is still standing on the window after it moves")

        // A screen full of windows must not turn the floor into a ceiling.
        perched.platforms = [WindowPlatform(
            windowNumber: 43,
            ownerName: "Fullscreen",
            rect: CGRect(x: 0, y: 0, width: 1440, height: 860)
        )]
        perched.move(to: CGPoint(x: 300, y: 0), animated: false)
        for _ in 0..<120 { perched.advance(dt: 1.0 / 60.0) }
        check(abs(perched.origin.y) < 1.0, "a window taller than the usable area is not a perch")

        print("")
        print("perch pump")
        let pump = PerchPump()
        let pumpDesktop = Desktop(visibleFrames: [CGRect(x: 0, y: 0, width: 1440, height: 860)])
        let pumpMotion = PetMotion(origin: CGPoint(x: 300, y: 700), size: size, desktop: pumpDesktop)
        pumpMotion.wanderEnabled = false
        pumpMotion.followCursor = false
        var feed: [WindowPlatform] = [window]
        pump.scan = { _ in feed }

        // The first update must scan: a cat that spawns above a window has to
        // know it is there before she falls past it.
        pump.update(motion: pumpMotion, dt: 0.001)
        check(pumpMotion.platforms.count == 1, "the first pump update scans immediately")

        // Riding: the window moves, she goes with it and stays on it.
        let anchored = pumpMotion.origin
        feed = [WindowPlatform(
            windowNumber: 42,
            ownerName: "Test",
            rect: window.rect.offsetBy(dx: 60, dy: -40)
        )]
        pump.update(motion: pumpMotion, dt: PerchPump.perchedInterval + 0.01)
        check(
            abs(pumpMotion.origin.x - anchored.x - 60) < 0.01 && abs(pumpMotion.origin.y - anchored.y + 40) < 0.01,
            "the pump carries her along when her window moves"
        )
        check(pumpMotion.supportPlatform()?.windowNumber == 42, "she is still on the window after the pump moves her")

        // Cadence: perched scans are frequent, idle scans are not.
        let perchedInterval = PerchPump.perchedInterval
        check(!pump.update(motion: pumpMotion, dt: perchedInterval / 2), "perched scanning is rate limited")
        check(pump.update(motion: pumpMotion, dt: perchedInterval), "perched scanning keeps up")
        pumpMotion.perchEnabled = false
        pump.update(motion: pumpMotion, dt: 10)
        check(pumpMotion.platforms.isEmpty, "turning perching off clears the platform list")

        print("")
        print("taps")
        // The click-to-talk path hangs off this: a press and release in the same
        // place is a pet, anything else is a throw.
        check(PetView.isTap(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 101, y: 101), held: 0.1), "a quick click in place is a tap")
        check(!PetView.isTap(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 140, y: 100), held: 0.1), "a drag is not a tap")
        check(!PetView.isTap(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 100, y: 100), held: 1.2), "a long press is not a tap")

        print("")
        print("jumping onto windows by herself")
        // She is on the floor at y=62. A window whose top is 300 pt up, wide
        // enough and far enough from the screen edge to stand on fully visible.
        let reachable = WindowPlatform(
            windowNumber: 51,
            ownerName: "Reachable",
            rect: CGRect(x: 200, y: 100, width: 600, height: 262)
        )
        // A screen tall enough that a high ledge is standable but still out of
        // reach, so the reach limit is what the test is measuring.
        let jumperDesktop = Desktop(visibleFrames: [CGRect(x: 0, y: 0, width: 1440, height: 1600)])
        let jumper = PetMotion(origin: CGPoint(x: 300, y: 0), size: size, desktop: jumperDesktop)
        jumper.wanderEnabled = false
        jumper.followCursor = false
        jumper.platforms = [reachable]

        guard let plan = jumper.planJump() else {
            check(false, "she plans a jump onto a reachable window")
            return 1
        }
        check(plan.velocity.dy > 0, "the jump goes up (vy=\(Int(plan.velocity.dy))pt/s)")
        check(
            abs(plan.target.y - reachable.top) < 0.01 && plan.target.x >= reachable.rect.minX && plan.target.x <= reachable.rect.maxX - size.width,
            "the jump aims at a spot on the ledge"
        )
        check(hypot(plan.velocity.dx, plan.velocity.dy) <= 2600, "the launch stays inside the physics speed cap")

        check(jumper.requestJump(), "she starts a jump when there is somewhere to go")
        check(jumper.isCrouching, "she gathers before launching")
        var reachedWindow = false
        for _ in 0..<420 {
            jumper.advance(dt: 1.0 / 60.0)
            if jumper.supportPlatform()?.windowNumber == 51 { reachedWindow = true }
        }
        check(reachedWindow, "she lands on the window top and stays there")
        check(abs(jumper.origin.y - reachable.top) < 1.5, "her feet end up on the ledge (y=\(String(format: "%.1f", jumper.origin.y)))")
        check(
            abs(jumper.origin.x - plan.target.x) < 12,
            "she lands where she aimed (x=\(String(format: "%.0f", jumper.origin.x)), aimed at \(String(format: "%.0f", plan.target.x)))"
        )
        check(jumper.jumpCount == 1, "the jump is counted once")

        // Left alone, she finds her own way up.
        let idle = PetMotion(origin: CGPoint(x: 300, y: 0), size: size, desktop: jumperDesktop)
        idle.followCursor = false
        idle.platforms = [reachable]
        var everPerched = false
        for _ in 0..<3600 {
            idle.advance(dt: 1.0 / 60.0)
            if idle.supportPlatform()?.windowNumber == 51 { everPerched = true }
        }
        check(everPerched, "left alone, she jumps onto the window within a minute")

        // The rule the feature exists for: a ledge she could not stand on
        // without being clipped at the screen edge is not a jump target.
        let edge = PetMotion(origin: CGPoint(x: 400, y: 0), size: size, desktop: jumperDesktop)
        edge.followCursor = false
        edge.platforms = [WindowPlatform(
            windowNumber: 52,
            ownerName: "Edge",
            rect: CGRect(x: -150, y: 100, width: 250, height: 262)
        )]
        check(
            edge.planJump() == nil,
            "a window top at the screen edge, too narrow to stand on fully visible, is not a jump target"
        )

        // The same window, but wide enough that she fits on screen: she jumps.
        let edgeWide = PetMotion(origin: CGPoint(x: 400, y: 0), size: size, desktop: jumperDesktop)
        edgeWide.followCursor = false
        edgeWide.platforms = [WindowPlatform(
            windowNumber: 53,
            ownerName: "EdgeWide",
            rect: CGRect(x: -150, y: 100, width: 900, height: 262)
        )]
        check(edgeWide.planJump() != nil, "the same ledge jumps when there is room to stand fully visible")

        // Out of reach, too narrow, or asleep: no jump.
        let far = PetMotion(origin: CGPoint(x: 300, y: 0), size: size, desktop: jumperDesktop)
        far.followCursor = false
        far.platforms = [WindowPlatform(
            windowNumber: 54,
            ownerName: "High",
            rect: CGRect(x: 200, y: 400, width: 600, height: 800)
        )]
        check(far.planJump() == nil, "a ledge above her reach is not a jump target")

        let narrow = PetMotion(origin: CGPoint(x: 300, y: 0), size: size, desktop: jumperDesktop)
        narrow.followCursor = false
        narrow.platforms = [WindowPlatform(
            windowNumber: 55,
            ownerName: "Narrow",
            rect: CGRect(x: 200, y: 100, width: 120, height: 262)
        )]
        check(narrow.planJump() == nil, "a ledge narrower than the cat is not a jump target")

        let talking = PetMotion(origin: CGPoint(x: 300, y: 0), size: size, desktop: jumperDesktop)
        talking.followCursor = false
        talking.platforms = [reachable]
        talking.isTalking = true
        check(!talking.requestJump(), "she does not jump out from under a sentence")
        talking.isTalking = false
        talking.jumpEnabled = false
        check(!talking.requestJump(), "the jump toggle is respected")

        // Sleep is a real state, not a flag: run her alone for a few minutes
        // with jumping off, then re-enable it and ask.
        let sleepy = PetMotion(origin: CGPoint(x: 300, y: 0), size: size, desktop: jumperDesktop)
        sleepy.wanderEnabled = false
        sleepy.followCursor = false
        sleepy.platforms = [reachable]
        sleepy.jumpEnabled = false
        for _ in 0..<9600 { sleepy.advance(dt: 1.0 / 60.0) }
        check(sleepy.isAsleep, "left alone for minutes, she is asleep")
        sleepy.jumpEnabled = true
        check(!sleepy.requestJump(), "a sleeping cat does not suddenly leap")

        print("")
        print("speech")
        let speech = SpeechEngine()
        let t0 = 100.0
        check(speech.say("hello", now: t0) == .started, "say opens a bubble")
        check(speech.bubble?.text == "hello", "the bubble holds the line")
        check(speech.isSpeaking, "the engine reports that she is speaking")
        if case .rateLimited(let retry) = speech.say("psst", now: t0 + 0.2) {
            check(retry > 0, "a second line inside the gap is rate limited (retry in \(String(format: "%.2f", retry))s)")
        } else {
            check(false, "a second line inside the gap is rate limited")
        }
        check(speech.say("later", now: t0 + 3) == .replaced, "a later line replaces the current bubble")
        let openId = speech.bubble?.id ?? ""
        check(speech.append(" more", to: openId, final: true, now: t0 + 3) == .started, "bubble.append grows the open bubble")
        check(speech.bubble?.text == "later more", "the appended text is in the bubble")
        check(speech.bubble?.streaming == false, "a final append closes the stream")
        check(speech.append("x", to: "nope", now: t0) == .rejected("unknown_bubble"), "appending to an unknown bubble is rejected")
        check(speech.say("   ", now: t0) == .rejected("empty_text"), "an empty line is rejected")
        check(speech.tick(now: t0 + 0.5) == false, "a fresh bubble does not expire early")
        check(speech.tick(now: t0 + 200), "a bubble past its TTL expires")
        check(!speech.isSpeaking, "the expired bubble is gone")
        check(speech.hide(now: t0 + 201) == false, "hiding when nothing is shown is a no-op")
        check(speech.say("bye", now: t0 + 300) == .started, "say works again after an expiry")
        check(speech.hide(now: t0 + 301), "hide dismisses the bubble")
        check(!speech.isSpeaking, "the dismissed bubble is gone")
        speech.enabled = false
        check(speech.say("muted", now: t0 + 400) == .rejected("muted"), "a muted engine refuses to speak")
        check(SpeechEngine.duration(for: "hi") >= 2 && SpeechEngine.duration(for: String(repeating: "x", count: 400)) <= 9, "the dismiss timer is length-derived and bounded")

        print("")
        print("bubble layout")
        for style in BubbleStyle.allCases {
            let short = BubbleContent(id: "a", text: "Done. 3 files changed.", style: style, streaming: false, expiresAt: .infinity)
            let bubbleSize = BubbleRenderer.windowSize(for: short)
            check(
                bubbleSize.width >= 60 && bubbleSize.width <= BubbleRenderer.maxTextWidth + 2 * BubbleRenderer.padding + 1,
                "\(style.rawValue) bubble is wide enough for its text and no wider than the wrap limit"
            )
            check(bubbleSize.height >= BubbleRenderer.padding * 2 + BubbleRenderer.tailHeight + 10, "\(style.rawValue) bubble has room for a line of text and the tail")
            let ink = bubbleInk(short, size: bubbleSize)
            check(ink.textPixels > 20, "\(style.rawValue) bubble renders its text headlessly (\(ink.textPixels) text pixels)")
            check(ink.cornerIsClear, "\(style.rawValue) bubble keeps a transparent corner outside the rounded card")
            check(ink.tailIsOpaque, "\(style.rawValue) bubble draws its tail")
        }
        let long = BubbleContent(id: "b", text: String(repeating: "the cat sat on the mat ", count: 12), style: .plain, streaming: false, expiresAt: .infinity)
        let longSize = BubbleRenderer.windowSize(for: long)
        check(longSize.width <= BubbleRenderer.maxTextWidth + 2 * BubbleRenderer.padding + 1, "a long line wraps instead of widening the bubble")
        check(longSize.height > BubbleRenderer.windowSize(for: BubbleContent(id: "c", text: "short", style: .plain, streaming: false, expiresAt: .infinity)).height, "wrapping makes the bubble taller")

        print("")
        print("resting shapes and the stretch")
        // Every shape has to keep something on the ground line: the physics
        // treats the window's bottom edge as the floor, so a shape whose belly
        // hovers reads as standing on nothing.
        for shape in CatShape.allCases {
            let anatomy = CatAnatomy.keyframe(shape)
            check(
                abs(anatomy.groundContact - CatGeometry.feetY) < 0.75,
                "\(shape.rawValue) rests on the ground line (contact y=\(String(format: "%.1f", anatomy.groundContact)))"
            )
        }

        // A blend is an average of the tables, so half way between standing and
        // a loaf has to be literally half way: that is the whole reason a
        // posture change cannot read as a hard cut.
        let halfLoaf = CatAnatomy.blend(.lerp(.only(.stand), .only(.loaf), 0.5))
        let expectedBodyY = (CatAnatomy.stand.bodyCenter.y + CatAnatomy.loaf.bodyCenter.y) / 2
        let expectedHeadY = (CatAnatomy.stand.headCenter.y + CatAnatomy.loaf.headCenter.y) / 2
        check(
            abs(halfLoaf.bodyCenter.y - expectedBodyY) < 0.001 && abs(halfLoaf.headCenter.y - expectedHeadY) < 0.001,
            "a half-settled loaf is the average of the two keyframes"
        )

        // Weights are an average, so they must never drift off 1.
        var weights = CatShapeWeights()
        for _ in 0..<200 { weights.approach(.stretch, by: 0.03) }
        check(
            abs(weights.total - 1) < 1e-9 && abs(weights[.stretch] - 1) < 1e-9,
            "shape weights stay normalised and do reach the target"
        )

        // The lean is damped for the low, wide shapes, which is what keeps them
        // inside the stage without the window growing.
        var leanProbe = CatPose()
        leanProbe.mood = .idle
        check(leanProbe.clampedForRender().tilt == 0, "a standing cat's lean limit is unchanged")
        leanProbe.tilt = 1
        check(
            abs(leanProbe.clampedForRender().tilt - CatPose.RenderLimits.tilt) < 1e-9,
            "a standing cat can still lean the full amount"
        )
        var loafProbe = CatPose()
        loafProbe.shape = .only(.loaf)
        loafProbe.tilt = 1
        check(
            loafProbe.clampedForRender().tilt < CatPose.RenderLimits.tilt * 0.6,
            "a loaf cannot lean like a standing cat (limit \(String(format: "%.3f", loafProbe.clampedForRender().tilt)) rad)"
        )

        /// Run a motion for `seconds` of simulated time at the fixed 60 Hz step.
        func run(_ motion: PetMotion, _ seconds: Double) {
            for _ in 0..<Int((seconds * 60).rounded()) { motion.advance(dt: 1.0 / 60.0) }
        }

        let restDesktop = Desktop(visibleFrames: [CGRect(x: 0, y: 0, width: 1440, height: 860)])
        let sitter = PetMotion(origin: CGPoint(x: 300, y: 0), size: size, desktop: restDesktop)
        sitter.wanderEnabled = false
        sitter.followCursor = false
        sitter.stretchAfterSeconds = 3
        sitter.sitAfterSeconds = 5
        sitter.sleepAfterSeconds = 12
        check(sitter.shape == .stand, "she starts out standing")

        run(sitter, 3.6)
        check(sitter.isStretching, "after a long idle she stretches")
        check(sitter.shape == .stretch, "the stretch is the shape she is wearing while she yawns")
        check(CatRenderer.yawnAmount(sitter.pose) > 0.4, "the yawn is open at the top of the stretch")

        run(sitter, 3.4)
        check(!sitter.isStretching, "the stretch ends on its own")
        check(sitter.shape == .sit, "before she falls asleep she sits down")
        check(!sitter.isStretching, "one stretch per idle period, not a tic")

        run(sitter, 6.0)
        check(sitter.isAsleep, "left alone long enough, she is asleep")
        check(sitter.shape == .lie, "asleep, she lies down rather than standing or sitting")

        sitter.noteInteraction()
        run(sitter, 0.4)
        check(sitter.isStretching, "waking up, she stretches again")
        run(sitter, 2.4)
        check(sitter.shape == .stand, "the waking stretch finishes back on her feet")

        // The loaf belongs to the perch, not to idleness: a cat on the floor
        // does not tuck her paws under.
        let floorCat = PetMotion(origin: CGPoint(x: 300, y: 0), size: size, desktop: restDesktop)
        floorCat.wanderEnabled = false
        floorCat.followCursor = false
        floorCat.loafAfterSeconds = 2
        floorCat.sitAfterSeconds = 10_000
        run(floorCat, 4)
        check(floorCat.shape == .stand, "on the floor she stands rather than loafing")

        let ledge = WindowPlatform(
            windowNumber: 77,
            ownerName: "Loaf",
            rect: CGRect(x: 200, y: 300, width: 600, height: 400)
        )
        let loafer = PetMotion(origin: CGPoint(x: 300, y: 700), size: size, desktop: restDesktop)
        loafer.wanderEnabled = false
        loafer.followCursor = false
        loafer.loafAfterSeconds = 2
        loafer.sitAfterSeconds = 10_000
        loafer.platforms = [ledge]
        loafer.move(to: CGPoint(x: 300, y: 702), animated: false)
        run(loafer, 0.9)
        check(loafer.supportPlatform()?.windowNumber == 77, "she is perched on the window")
        // Pin the hold after landing: the fresh-perch edge jitters it, and the
        // selftest wants a loaf it can time.
        loafer.loafHoldSeconds = 2.5
        run(loafer, 1.5)
        check(loafer.restingShape == .loaf, "after a long perch the ladder asks for a loaf")
        run(loafer, 0.9)
        check(loafer.shape == .loaf, "the loaf is what she ends up wearing")
        check(loafer.isResting, "the loaf counts as resting")
        run(loafer, 2.0)
        check(loafer.shape == .stand, "the loaf ends on its own and she gets up again")

        // And a settled cat stays settled. Before this, the wander scheduler
        // would stand her back up every few seconds, which made the sit a twitch
        // and let a "sleeping" cat walk off mid-nap.
        let parked = PetMotion(origin: CGPoint(x: 300, y: 0), size: size, desktop: restDesktop)
        parked.followCursor = false
        parked.sitAfterSeconds = 1
        run(parked, 2.5)
        check(parked.shape == .sit, "left alone on the floor she sits down")
        let sittingX = parked.origin.x
        run(parked, 60)
        check(abs(parked.origin.x - sittingX) < 0.5, "once she has sat down she stays put")
        run(parked, 95)
        check(parked.isAsleep, "and a couple of minutes later she is asleep")
        check(parked.shape == .lie, "asleep, she is lying down")
        check(abs(parked.origin.x - sittingX) < 0.5, "a sleeping cat does not wander off mid-nap")

        print("")
        print("settling is an animation, not a hard cut")
        /// Biggest single-frame movement of a body or head anchor, in design
        /// units. A keyframe switch would show up here as tens of units.
        func settleStep(_ motion: PetMotion, _ seconds: Double) -> CGFloat {
            var previous: CatAnatomy?
            var biggest: CGFloat = 0
            for _ in 0..<Int((seconds * 60).rounded()) {
                motion.advance(dt: 1.0 / 60.0)
                let anatomy = motion.pose.anatomy
                if let previous {
                    biggest = max(biggest, hypot(
                        anatomy.bodyCenter.x - previous.bodyCenter.x,
                        anatomy.bodyCenter.y - previous.bodyCenter.y
                    ))
                    biggest = max(biggest, hypot(
                        anatomy.headCenter.x - previous.headCenter.x,
                        anatomy.headCenter.y - previous.headCenter.y
                    ))
                }
                previous = anatomy
            }
            return biggest
        }

        let settling = PetMotion(origin: CGPoint(x: 300, y: 0), size: size, desktop: restDesktop)
        settling.wanderEnabled = false
        settling.followCursor = false
        settling.sleepAfterSeconds = 1
        let settleStepMax = settleStep(settling, 3)
        print(String(format: "  info a stand-to-lie settle never moves an anchor more than %.2f design units per frame", settleStepMax))
        check(settleStepMax < 0.75, "settling from standing to asleep is a continuous morph")
        check(settling.shape == .lie, "and it arrives at the lie")

        // The awkward case the weight vector exists for: she starts sitting
        // down and dozes off before the sit has finished. Retargeting must not
        // pop.
        let changing = PetMotion(origin: CGPoint(x: 300, y: 0), size: size, desktop: restDesktop)
        changing.wanderEnabled = false
        changing.followCursor = false
        changing.sitAfterSeconds = 1
        changing.sleepAfterSeconds = 1.5
        let retargetMax = settleStep(changing, 3)
        print(String(format: "  info retargeting sit->lie mid-settle peaks at %.2f design units per frame", retargetMax))
        check(retargetMax < 0.75, "changing her mind mid-settle does not pop")

        // The stretch timeline itself, without running the animation.
        check(PetMotion.stretchCurve(0) == 0, "the stretch starts at rest")
        check(PetMotion.stretchCurve(1) == 0, "the stretch ends at rest")
        check(PetMotion.stretchCurve(0.45) == 1, "the stretch holds at the top of the bow")
        check(PetMotion.stretchCurve(0.14) > 0 && PetMotion.stretchCurve(0.14) < 1, "the stretch eases in")
        check(CatRenderer.yawnAmount(CatPose()) == 0, "a standing cat is not yawning")

        let held = PetMotion(origin: CGPoint(x: 300, y: 0), size: size, desktop: restDesktop)
        held.wanderEnabled = false
        held.followCursor = false
        held.isTalking = true
        check(!held.beginStretch(), "she does not stretch out from under a sentence")
        held.isTalking = false
        held.beginDrag(at: CGPoint(x: 300, y: 0))
        check(!held.beginStretch(), "she does not stretch while being carried")

        print("")
        print("frame tiers")
        // The reported bug: a cat thrown with the mouse fell at the idle tier.
        let tier = PetWindowController.desiredInterval
        check(tier(true, false, false, false, .idle) == 1.0 / 60.0, "dragging runs at display rate")
        check(tier(false, true, false, false, .idle) == 1.0 / 60.0, "a thrown cat never falls at the idle tier")
        check(tier(false, true, false, false, .sleepy) == 1.0 / 60.0, "even a sleepy cat thrown in the air runs at display rate")
        check(tier(false, false, true, false, .idle) == 1.0 / 30.0, "the landing squash is not drawn at the sleep tier")
        // Same argument as the thrown cat: a settle into a loaf and a waking
        // stretch are both short animations, and at 8 fps they are a slideshow.
        check(tier(false, false, true, false, .sleepy) == 1.0 / 30.0, "a settle or a stretch is never drawn at the sleep tier")
        check(tier(false, false, false, true, .idle) == 1.0 / 30.0, "a hovered cat animates at 30 fps")
        check(tier(false, false, false, false, .idle) == 1.0 / 15.0, "an idle cat drops to 15 fps")
        check(tier(false, false, false, false, .sleepy) == 1.0 / 8.0, "a sleeping cat drops to 8 fps")

        // And that a real throw actually reaches the airborne state the tier
        // table keys off, rather than trusting the flag by construction.
        let tossed = PetMotion(origin: CGPoint(x: 400, y: 400), size: size, desktop: desktop)
        tossed.wanderEnabled = false
        tossed.followCursor = false
        tossed.beginDrag(at: CGPoint(x: 400, y: 400))
        tossed.updateDrag(to: CGPoint(x: 460, y: 520))
        tossed.endDrag()
        tossed.advance(dt: 1.0 / 60.0)
        check(tossed.isAirborne, "a released cat is airborne, so the pump stays at display rate")
        check(!tossed.isDragging, "she is no longer being held")

        print("")
        print("fling across a two-display layout")
        let dual = Desktop(visibleFrames: [
            CGRect(x: 0, y: 62, width: 3840, height: 1528),
            CGRect(x: 3840, y: 0, width: 1440, height: 2560),
        ])
        let flung = PetMotion(origin: CGPoint(x: 3620, y: 86), size: size, desktop: dual)
        flung.wanderEnabled = false
        flung.followCursor = false
        // Simulate an actual fast drag: the pointer must move over real time,
        // because release velocity is derived from timestamped samples.
        flung.beginDrag(at: CGPoint(x: 3690, y: 150))
        var pointer = CGPoint(x: 3690, y: 150)
        for _ in 0..<6 {
            flung.advance(dt: 1.0 / 60.0)
            pointer.x += 40
            pointer.y += 12
            flung.updateDrag(to: pointer)
        }
        flung.endDrag()
        print("  info release velocity=\(Int(hypot(flung.velocity.dx, flung.velocity.dy)))pt/s")

        var settleSeconds = 0.0
        var furthest = 0.0
        var topOfTravel = CGFloat(0)
        for step in 0..<3000 {
            flung.advance(dt: 1.0 / 60.0)
            settleSeconds = Double(step) / 60.0
            furthest = max(furthest, hypot(flung.origin.x - 3620, flung.origin.y - 86))
            topOfTravel = max(topOfTravel, flung.origin.y)
            if abs(flung.velocity.dx) < 1 && abs(flung.velocity.dy) < 1 { break }
        }
        print("  info travel=\(Int(furthest))pt peakY=\(Int(topOfTravel)) settled after \(String(format: "%.1f", settleSeconds))s")
        check(settleSeconds < 20, "a hard fling comes to rest within 20s")
        check(furthest < 4000, "a hard fling does not travel absurdly far (\(Int(furthest))pt)")

        print("")
        print("teleporting between displays")
        let twinDesk = Desktop(visibleFrames: [
            CGRect(x: 0, y: 0, width: 1440, height: 860),
            CGRect(x: 1440, y: 0, width: 1920, height: 1080),
        ])

        let traveller = PetMotion(origin: CGPoint(x: 600, y: 0), size: size, desktop: twinDesk)
        traveller.wanderEnabled = false
        traveller.followCursor = false
        traveller.sleepAfterSeconds = 10_000
        traveller.teleportEnabled = false
        traveller.teleportInSeconds = 1
        run(traveller, 20)
        check(traveller.teleportCount == 0, "with teleporting off she stays on the display she is on")

        traveller.teleportEnabled = true
        traveller.teleportInSeconds = 2
        run(traveller, 5)
        check(traveller.teleportCount == 1, "with teleporting on she blinks to the other display")
        check(
            twinDesk.visibleFrames[1].contains(traveller.origin),
            "and she arrives inside the other display, not off the side of it"
        )

        // Arriving on a window top rather than in front of it. She is on the
        // second display by now, so the on-demand hop takes her back to the
        // first, where this ledge spans the whole width she can land in.
        let homeLedge = WindowPlatform(
            windowNumber: 88,
            ownerName: "Home",
            rect: CGRect(x: 0, y: 100, width: 1440, height: 550)
        )
        traveller.platforms = [homeLedge]
        check(traveller.teleportToRandomScreen(), "she can also be sent across on demand")
        check(twinDesk.visibleFrames[0].contains(traveller.origin), "and she arrives on the display she was sent to")
        check(abs(traveller.origin.y - homeLedge.top) < 0.01, "she lands on the window top, not in front of it")
        check(traveller.supportPlatform()?.windowNumber == 88, "and the perch system knows she is standing on it")

        let soloDesk = Desktop(visibleFrames: [CGRect(x: 0, y: 0, width: 1440, height: 860)])
        let solo = PetMotion(origin: CGPoint(x: 600, y: 0), size: size, desktop: soloDesk)
        solo.wanderEnabled = false
        solo.followCursor = false
        solo.sleepAfterSeconds = 10_000
        solo.teleportEnabled = true
        solo.teleportInSeconds = 1
        run(solo, 20)
        check(solo.teleportCount == 0, "with one display there is nowhere to blink to")

        let carried = PetMotion(origin: CGPoint(x: 600, y: 0), size: size, desktop: twinDesk)
        carried.followCursor = false
        carried.sleepAfterSeconds = 10_000
        carried.teleportEnabled = true
        carried.teleportInSeconds = 1
        carried.beginDrag(at: CGPoint(x: 600, y: 0))
        run(carried, 10)
        check(carried.teleportCount == 0, "she does not blink out of your hand")

        // The blink is staged: she spins down to nothing, the move happens while
        // she is not on screen to see it, and then she spins back in.
        let blinker = PetMotion(origin: CGPoint(x: 600, y: 0), size: size, desktop: twinDesk)
        blinker.wanderEnabled = false
        blinker.followCursor = false
        blinker.sleepAfterSeconds = 10_000
        check(!blinker.isTeleporting, "she is not blinking to start with")
        check(blinker.beginTeleport(), "a blink can start")
        check(blinker.teleportPhase == .leaving, "and it starts by leaving")

        let halfBlink = PetMotion.teleportHalfSeconds
        run(blinker, halfBlink * 0.5)
        check(
            blinker.pose.vanish > 0.3,
            "half way out she is part way gone (vanish=\(String(format: "%.2f", blinker.pose.vanish)))"
        )
        check(abs(blinker.origin.x - 600) < 0.01, "and she has not moved yet")
        check(!blinker.canStretch, "a cat mid-blink does not stop to stretch")

        run(blinker, halfBlink * 0.5 + 0.02)
        check(blinker.teleportPhase == .arriving, "then the move happens and she is arriving")
        check(blinker.teleportCount == 1, "one blink, one move")
        check(twinDesk.visibleFrames[1].contains(blinker.origin), "and she arrives on the other display")
        check(
            blinker.pose.vanish > 0.8,
            "arriving starts out still gone (vanish=\(String(format: "%.2f", blinker.pose.vanish)))"
        )

        run(blinker, halfBlink + 0.02)
        check(!blinker.isTeleporting, "the blink ends")
        check(blinker.pose.vanish == 0, "with her fully back on screen")
        check(blinker.isSettling, "and a landing squash to sell it")

        // The user's hand outranks an effect in progress.
        let interrupted = PetMotion(origin: CGPoint(x: 600, y: 0), size: size, desktop: twinDesk)
        interrupted.followCursor = false
        check(interrupted.beginTeleport(), "she can start a blink")
        run(interrupted, halfBlink * 0.4)
        check(interrupted.pose.vanish > 0, "and is part way gone")
        interrupted.beginDrag(at: CGPoint(x: 600, y: 0))
        run(interrupted, 1.0 / 60.0)
        check(
            !interrupted.isTeleporting && interrupted.pose.vanish == 0,
            "grabbing her mid-blink cancels it"
        )

        let nowhere = PetMotion(origin: CGPoint(x: 600, y: 0), size: size, desktop: soloDesk)
        nowhere.followCursor = false
        check(!nowhere.beginTeleport(), "with one display there is nowhere to blink to")

        print("")
        print("what a pet offers when you right-click it")
        // The menu is built from a value, so its shape is checkable without a
        // colony or a window server — and its shape is the whole point: before
        // this, the only way to take a pet off the desk was the menu bar's
        // remove, which always took the newest.
        let petMenu = AppDelegate.petMenu(
            for: AppDelegate.PetMenuState(
                index: 1,
                species: .bunny,
                coat: .snow,
                count: 3,
                isHidden: false,
                isDefault: false,
                someHidden: true
            ),
            target: nil
        )
        print("  info menu: " + petMenu.items.map(\.title).joined(separator: " | "))
        check(petMenu.items.contains { $0.title == "Hide this critter" }, "it offers to hide *this* pet")
        check(
            petMenu.items.first { $0.title == "Hide this critter" }?.tag == 1,
            "and the item names the pet you clicked, not the newest one"
        )
        check(
            petMenu.items.first { $0.title == "Remove this critter" }?.tag == 1,
            "removal names the clicked pet too"
        )
        check(petMenu.items.contains { $0.title == "Show all critters" }, "and the hidden ones can come back")
        check(petMenu.items.contains { $0.title == "Bunny · Snow" }, "the menu says which animal it is")
        check(petMenu.items.contains { $0.title == "Bring this one home" }, "and can put it back on the floor")

        let hiddenMenu = AppDelegate.petMenu(
            for: AppDelegate.PetMenuState(
                index: 0,
                species: .cat,
                coat: .tabby,
                count: 1,
                isHidden: true,
                isDefault: true,
                someHidden: false
            ),
            target: nil
        )
        check(
            hiddenMenu.items.contains { $0.title == "Show this critter" },
            "a hidden pet's own menu offers to show it again"
        )
        check(
            hiddenMenu.items.first { $0.title == "Remove this critter" }?.isEnabled == false,
            "and the last pet cannot be removed"
        )
        check(
            hiddenMenu.items.contains { $0.title.hasPrefix("Cat · Tabby") && $0.title.contains("(default)") },
            "the pet that answers producers is marked as the default"
        )
        check(
            !hiddenMenu.items.contains { $0.title == "Show all critters" },
            "with nobody else hidden there is nothing to bring back"
        )

        // Hiding a pet has to be free, or "hide the one I am pointing at" is a
        // worse deal than removing it.
        let dormantDesk = Desktop(visibleFrames: [CGRect(x: 0, y: 0, width: 1440, height: 860)])
        let dormant = PetMotion(origin: CGPoint(x: 300, y: 0), size: size, desktop: dormantDesk)
        dormant.followCursor = false
        dormant.wanderEnabled = true
        dormant.sitAfterSeconds = 10_000
        dormant.isPaused = true
        let restedAt = dormant.origin
        run(dormant, 8)
        check(dormant.origin == restedAt, "a hidden pet does not move while it is hidden")
        dormant.isPaused = false
        run(dormant, 8)
        check(dormant.origin != restedAt, "and picks up where it left off when it comes back")

        // A hidden pet is not drawn, so it should not hold a share of the budget.
        check(
            PetCohort.frameShare(total: 5, hidden: 2) == PetCohort.perPetFPS(petCount: 3),
            "hiding two of five gives the rest the three-pet frame rate"
        )
        check(
            PetCohort.frameShare(total: 5, hidden: 5) == PetCohort.perPetFPS(petCount: 1),
            "and hiding all of them does not divide by zero"
        )

        print("")
        print("scuffles")
        let scuffleDesk = Desktop(visibleFrames: [CGRect(x: 0, y: 0, width: 1440, height: 860)])
        // The close-quarters version of playing: two animals who are already next
        // to each other bat at each other instead of chasing.
        let scrappy = PetMotion(origin: CGPoint(x: 300, y: 0), size: size, desktop: scuffleDesk)
        scrappy.followCursor = false
        let rival = CGPoint(x: 300 + scrappy.personalSpace * 0.9, y: 0)
        scrappy.companions = [rival]
        check(!scrappy.isScuffling, "she is not scrapping to start with")
        check(scrappy.startScuffle(2), "a scrap can start")
        check(scrappy.isScuffling, "and then she is scrapping")

        var sawHop = false
        var sawHiss = false
        for _ in 0..<90 {
            scrappy.companions = [rival]
            scrappy.advance(dt: 1.0 / 60.0)
            if scrappy.pose.hopOffset > 0.5 { sawHop = true }
            if scrappy.pose.mouthOpen > 0.3 { sawHiss = true }
        }
        check(sawHop, "she hops at her rival")
        check(sawHiss, "and hisses at her")
        check(scrappy.pose.mood == .alarmed, "wearing the flattened-ear face while she does it")
        check(scrappy.facingDirection > 0, "and facing her, who is to her right")
        run(scrappy, 2)
        check(!scrappy.isScuffling, "the scrap ends on its own")

        let dozing = PetMotion(origin: CGPoint(x: 300, y: 0), size: size, desktop: scuffleDesk)
        dozing.followCursor = false
        dozing.sleepAfterSeconds = 1
        run(dozing, 2)
        check(dozing.isAsleep && !dozing.startScuffle(2), "a sleeping animal does not get up to fight")

        let cradled = PetMotion(origin: CGPoint(x: 300, y: 0), size: size, desktop: scuffleDesk)
        cradled.followCursor = false
        cradled.beginDrag(at: CGPoint(x: 300, y: 0))
        check(!cradled.startScuffle(2), "and she does not fight out of your hand")

        print("")
        print("a colony of cats")
        // Ten coats, all different: two identical cats on one desk read as a
        // rendering bug rather than as two pets.
        check(
            CatSkin.allCases.count >= PetCohort.maximumPets,
            "there is a coat for every pet the cap allows (\(CatSkin.allCases.count))"
        )
        var coats = Set<String>()
        for skin in CatSkin.allCases {
            let components = skin.palette.fur.components ?? []
            coats.insert(components.map { String(format: "%.3f", $0) }.joined(separator: ","))
        }
        check(coats.count == CatSkin.allCases.count, "every coat is a different colour")
        check(CatSkin.allCases.allSatisfy { !$0.name.isEmpty }, "every coat has a name for the menu")

        // The cap and the budget are pure, so both can be pinned without a window
        // server: nine cats can have a tenth, ten cannot, and the budget divides.
        check(PetCohort.canAddPet(having: 0), "an empty desk can have a pet")
        check(PetCohort.canAddPet(having: PetCohort.maximumPets - 1), "the last slot is still a slot")
        check(!PetCohort.canAddPet(having: PetCohort.maximumPets), "the cap holds at \(PetCohort.maximumPets)")
        check(PetCohort.perPetFPS(petCount: 1) == 60, "one cat is not budget-limited")
        check(
            PetCohort.perPetFPS(petCount: PetCohort.maximumPets) >= 8,
            "five cats each still get at least the sleep tier (\(String(format: "%.0f", PetCohort.perPetFPS(petCount: PetCohort.maximumPets))) fps)"
        )
        check(
            PetCohort.perPetFPS(petCount: PetCohort.maximumPets) < PetCohort.perPetFPS(petCount: 2),
            "more pets means fewer frames each"
        )

        // Where a new cat appears. This rule used to override `--at x,y` silently,
        // which is exactly the kind of bug a pure function makes impossible.
        let desk = CGRect(x: 0, y: 62, width: 1440, height: 1528)
        let petSize = CatGeometry.preferredWindowSize
        let chosen = CGPoint(x: 800, y: 300)
        let first = PetCohort.homeOrigin(slot: 0, region: desk, size: petSize, start: chosen)
        let second = PetCohort.homeOrigin(slot: 1, region: desk, size: petSize, start: chosen)
        check(first == chosen, "the first cat of a colony starts exactly where --at put her")
        check(second.x > first.x && second.y == first.y, "and the next one lines up beside her")
        for slot in 0..<PetCohort.maximumPets {
            let origin = PetCohort.homeOrigin(slot: slot, region: desk, size: petSize, start: nil)
            check(
                origin.x >= desk.minX && origin.x + petSize.width <= desk.maxX && origin.y == desk.minY,
                "cat \(slot + 1) of an unplaced colony starts on the desk (\(Int(origin.x)))"
            )
        }
        let crowded = (0..<PetCohort.maximumPets).map {
            PetCohort.homeOrigin(slot: $0, region: desk, size: petSize, start: nil).x
        }
        check(Set(crowded).count == PetCohort.maximumPets, "the whole colony arrives in different places")

        // How often a pet blinks is a setting, and the jitter is what keeps five
        // of them from blinking in unison.
        check(
            TeleportCadence.allCases.map(\.minutes) == [1, 2, 5, 10, 30],
            "the cadence menu offers minutes, not milliseconds"
        )
        let patient = PetMotion(origin: CGPoint(x: 300, y: 0), size: size, desktop: twinDesk)
        patient.followCursor = false
        patient.teleportCadence = .rare
        patient.rescheduleTeleport()
        check(
            patient.teleportInSeconds >= TeleportCadence.rare.seconds * 0.65
                && patient.teleportInSeconds <= TeleportCadence.rare.seconds * 1.35,
            "and a pet's next blink lands inside the cadence it was given"
        )

        // The roster is what "load these pookies" means, so it survives a round
        // trip through the settings store.
        let roster: [CritterConfig] = [
            CritterConfig(species: .cat, coat: .tabby),
            CritterConfig(.panda),
            CritterConfig(species: .fox, coat: .midnight),
        ]
        let decoded = roster.map(\.encoded).compactMap(CritterConfig.init(encoded:))
        check(decoded == roster, "the roster survives being written down and read back")
        check(CritterConfig(encoded: "bunny:snow")?.species == .bunny, "a saved animal keeps its species")
        check(CritterConfig(encoded: "nonsense") == nil, "and a corrupt one is dropped rather than guessed at")

        // Five species, five shapes: nobody is wearing anyone else's silhouette.
        let silhouettes = PetSpecies.allCases.map { species -> String in
            let anatomy = CatAnatomy.stand.wearing(species.traits)
            return String(
                format: "%.1f/%.1f/%.1f",
                anatomy.headRadius, anatomy.bodyRadii.width, anatomy.pawOffsetX
            )
        }
        check(Set(silhouettes).count == PetSpecies.allCases.count, "every species has its own proportions")
        check(
            Set(PetSpecies.allCases.map(\.defaultCoat)).count == PetSpecies.allCases.count,
            "and a coat of its own to be recognised by"
        )
        for species in PetSpecies.allCases {
            let anatomy = CatAnatomy.stand.wearing(species.traits)
            check(
                abs(anatomy.groundContact - CatGeometry.feetY) < 1.0,
                "\(species.name) stands on the ground line (contact y=\(String(format: "%.1f", anatomy.groundContact)))"
            )
        }

        // Two cats converging on one spot read as one buggy cat, so they step
        // apart — positionally, so they settle instead of springing forever.
        let colonyDesk = Desktop(visibleFrames: [CGRect(x: 0, y: 0, width: 1440, height: 860)])
        let alice = PetMotion(origin: CGPoint(x: 600, y: 0), size: size, desktop: colonyDesk)
        let bob = PetMotion(origin: CGPoint(x: 610, y: 0), size: size, desktop: colonyDesk)
        alice.wanderEnabled = false
        alice.followCursor = false
        bob.wanderEnabled = false
        bob.followCursor = false
        for _ in 0..<600 {
            alice.companions = [bob.origin]
            bob.companions = [alice.origin]
            alice.advance(dt: 1.0 / 60.0)
            bob.advance(dt: 1.0 / 60.0)
        }
        let spacing = abs(alice.origin.x - bob.origin.x)
        check(
            spacing >= alice.personalSpace * 0.95,
            "two cats who start on top of each other step apart (\(String(format: "%.0f", spacing))pt of \(String(format: "%.0f", alice.personalSpace))pt)"
        )

        // Playing: a bout sends her at her playmate, wearing the happy face, and
        // it is refused whenever she is in no state to notice anyone.
        let chaser = PetMotion(origin: CGPoint(x: 200, y: 0), size: size, desktop: colonyDesk)
        chaser.followCursor = false
        check(!chaser.isPlaying, "she is not playing to start with")
        check(chaser.startPlay(3), "a bout can start")
        check(chaser.isPlaying, "and then she is playing")
        let startX = chaser.origin.x
        for _ in 0..<120 {
            chaser.companions = [CGPoint(x: 900, y: 0)]
            chaser.advance(dt: 1.0 / 60.0)
        }
        check(
            chaser.origin.x > startX + 20,
            "she runs at her playmate (\(String(format: "%.0f", chaser.origin.x - startX))pt in two seconds)"
        )
        check(chaser.pose.mood == .happy, "and she looks pleased about it")
        check(!chaser.canStretch, "a cat mid-chase does not stop to stretch")

        let napper = PetMotion(origin: CGPoint(x: 200, y: 0), size: size, desktop: colonyDesk)
        napper.followCursor = false
        napper.sleepAfterSeconds = 1
        run(napper, 2)
        check(napper.isAsleep, "she is asleep")
        check(!napper.startPlay(2), "and a sleeping cat does not get up to play")

        let grabbed = PetMotion(origin: CGPoint(x: 200, y: 0), size: size, desktop: colonyDesk)
        grabbed.followCursor = false
        grabbed.beginDrag(at: CGPoint(x: 200, y: 0))
        check(!grabbed.startPlay(2), "she does not start a game while you are holding her")
        check(!grabbed.isPlaying, "and she is not playing")

        print("")
        if failures.isEmpty {
            print("selftest PASSED")
            return 0
        }
        print("selftest FAILED (\(failures.count))")
        for failure in failures { print("  - \(failure)") }
        return 1
    }

    // MARK: - Art envelope helpers

    /// Ink boundary samples, in design space, for one shape keyframe: over every
    /// parameter that is not part of the pose transform — tail sway, ear twitch,
    /// breathing, blinks, gaze, mouth, blush, mood and facing.
    ///
    /// Boundary pixels rather than a bounding box: the cat is not a rectangle,
    /// and the difference is about ten design units of stage width.
    private static func inkPoints(renderer: CatRenderer, shape: CatShape, species: PetSpecies) -> [CGPoint] {
        let size = CatGeometry.preferredWindowSize
        let width = Int(size.width)
        let height = Int(size.height)
        let fit = CatGeometry.fit(in: size)

        var points: [CGPoint] = []
        var seen = Set<Int64>()

        for var pose in ArtSweep.oneFactorPoses() {
            pose.shape = .only(shape)
            pose.species = species
            let coverage = rasterise(renderer: renderer, size: size, pose: pose)
            for y in 0..<height {
                for x in 0..<width {
                    guard coverage[MaskRaster.index(x: x, y: y, width: width, height: height)] > 8 else { continue }
                    let isBoundary =
                        x == 0 || y == 0 || x == width - 1 || y == height - 1
                        || coverage[MaskRaster.index(x: x - 1, y: y, width: width, height: height)] <= 8
                        || coverage[MaskRaster.index(x: x + 1, y: y, width: width, height: height)] <= 8
                        || coverage[MaskRaster.index(x: x, y: y - 1, width: width, height: height)] <= 8
                        || coverage[MaskRaster.index(x: x, y: y + 1, width: width, height: height)] <= 8
                    guard isBoundary else { continue }

                    let point = CGPoint(
                        x: (CGFloat(x) - fit.origin.x) / fit.scale,
                        y: (CGFloat(y) - fit.origin.y) / fit.scale
                    )
                    // Quarter-unit buckets: enough resolution to bound the art,
                    // few enough points to keep this instant.
                    let key = Int64((point.x * 4).rounded()) &* 1_000_003 &+ Int64((point.y * 4).rounded())
                    guard seen.insert(key).inserted else { continue }
                    points.append(point)
                }
            }
        }
        return points
    }

    private static func bounds(of points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .null }
        var minX = points[0].x, maxX = points[0].x
        var minY = points[0].y, maxY = points[0].y
        for point in points {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Worst case of the pose transform applied to one shape's own ink.
    ///
    /// Per shape, not over one pooled cloud: the lean pivots about the body
    /// mass, and a standing cat's pivot applied to a loaf's ground-level tail
    /// would invent a pose the renderer can never produce.
    ///
    /// The transform is affine in scale and hop, so those extremes sit on the
    /// corners of the parameter box. Rotation is not linear, but the worst an
    /// interior angle can beat an endpoint by is `r * (1 - cos(limit))` — about
    /// 1.3 design units at the legal limit — which the pad below covers.
    private static func transformEnvelope(shape: CatShape, points: [CGPoint], species: PetSpecies) -> CGRect {
        let limits = CatPose.RenderLimits.self
        var union = CGRect.null

        for tilt in [-limits.tilt, 0, limits.tilt] {
            for stretch in [limits.minStretch, limits.maxStretch] {
                for squash in [limits.minSquash, limits.maxSquash] {
                    for hop in [0, limits.hop] {
                        for facing in [1.0, -1.0] {
                            var pose = CatPose()
                            pose.shape = .only(shape)
                            pose.species = species
                            pose.tilt = tilt
                            pose.stretch = stretch
                            pose.squash = squash
                            pose.hopOffset = hop
                            pose.facing = facing
                            let transform = CatGeometry.poseTransform(pose.clampedForRender())
                            for point in points {
                                union = union.union(
                                    CGRect(x: point.x, y: point.y, width: 0, height: 0).applying(transform)
                                )
                            }
                        }
                    }
                }
            }
        }
        // Rotation slack plus a pixel of antialiasing bleed.
        return union.insetBy(dx: -2, dy: -2)
    }

    /// Raw coverage, no dilation, antialiasing on: exactly what the window draws.
    private static func rasterise(renderer: CatRenderer, size: CGSize, pose: CatPose) -> [UInt8] {
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
            ) else { return }
            context.setShouldAntialias(true)
            renderer.draw(in: context, size: CGSize(width: width, height: height), pose: pose)
        }
        return buffer
    }

    /// The stage a blink needs.
    ///
    /// The blink is a transform *on top of* the pose, so the ink cloud the
    /// ordinary envelope is built from is the right thing to push through it —
    /// not the envelope rectangle, whose corners are empty air and would demand a
    /// stage half again as wide. Twenty-five steps of the twist, each applied to
    /// every sampled boundary point.
    ///
    /// The pad is 1.5 rather than the envelope's 2: the ordinary check takes three
    /// tilt samples and pays for the interior with slack, where this takes
    /// twenty-five steps and needs little more than a pixel of antialiasing bleed.
    private static func blinkEnvelope(shape: CatShape, points: [CGPoint], species: PetSpecies) -> CGRect {
        var union = CGRect.null
        for step in 0...24 {
            var pose = CatPose()
            pose.shape = .only(shape)
            pose.species = species
            pose.vanish = Double(step) / 24
            let transform = CatGeometry.vanishTransform(pose)
            for point in points {
                union = union.union(
                    CGRect(x: point.x, y: point.y, width: 0, height: 0).applying(transform)
                )
            }
        }
        return union.insetBy(dx: -1.5, dy: -1.5)
    }

    /// The window-space y of the lowest row that has any ink.
    ///
    /// This is the line she actually stands on: her window's bottom edge is
    /// deliberately below it (see `CatGeometry.groundInset`), and the selftest
    /// uses this to measure the gap between the two.
    private static func lowestInkY(_ coverage: [UInt8], width: Int, height: Int) -> CGFloat {
        for y in 0..<height {
            for x in 0..<width where coverage[MaskRaster.index(x: x, y: y, width: width, height: height)] > 8 {
                return CGFloat(y)
            }
        }
        return .greatestFiniteMagnitude
    }

    /// Every pixel the pupils cover, as a mean position in design space.
    ///
    /// Colour rather than geometry: the test this exists for is whether the
    /// renderer mirrors a gaze offset when the cat faces the other way, and the
    /// only honest way to ask is to look at where the dark pixels landed.
    private static func pupilCentroidX(renderer: CatRenderer, size: CGSize, pose: CatPose) -> CGFloat? {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        let fit = CatGeometry.fit(in: size)
        let pixels = rasteriseColour(renderer: renderer, size: size, pose: pose.clampedForRender())
        let eye = CatPalette.tabby.eye.components ?? [0, 0, 0, 1]
        let target = (
            r: Int((eye[0] * 255).rounded()),
            g: Int((eye[1] * 255).rounded()),
            b: Int((eye[2] * 255).rounded())
        )

        var sum: CGFloat = 0
        var count = 0
        for y in 0..<height {
            for x in 0..<width {
                let row = MaskRaster.rowZeroIsBottom ? y : (height - 1 - y)
                let index = (row * width + x) * 4
                guard pixels[index + 3] > 200 else { continue }
                let difference = abs(Int(pixels[index]) - target.r)
                    + abs(Int(pixels[index + 1]) - target.g)
                    + abs(Int(pixels[index + 2]) - target.b)
                guard difference <= 12 else { continue }
                sum += CGFloat(x)
                count += 1
            }
        }
        guard count > 20 else { return nil }
        return (sum / CGFloat(count) - fit.origin.x) / fit.scale
    }

    /// The cat in colour, for the tests that need to find a part of her rather
    /// than just her silhouette.
    private static func rasteriseColour(renderer: CatRenderer, size: CGSize, pose: CatPose) -> [UInt8] {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw -> Void in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.setShouldAntialias(true)
            renderer.draw(in: context, size: CGSize(width: width, height: height), pose: pose)
        }
        return buffer
    }

    /// Distance in pixels from the nearest ink to the closest window edge. Zero
    /// or less means the drawing is touching (and therefore losing) pixels.
    private static func edgeMargin(_ coverage: [UInt8], width: Int, height: Int) -> CGFloat {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where coverage[MaskRaster.index(x: x, y: y, width: width, height: height)] > 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return .greatestFiniteMagnitude }
        return CGFloat(min(minX, minY, width - 1 - maxX, height - 1 - maxY))
    }

    private static func describe(_ pose: CatPose) -> String {
        String(
            format: "tilt=%.2f stretch=%.2f squash=%.2f hop=%.1f tail=%.2f facing=%.0f vanish=%.2f",
            pose.tilt, pose.stretch, pose.squash, pose.hopOffset, pose.tailPhase, pose.facing, pose.vanish
        )
    }

    /// A mask with the bottom half covered, built through the same rasteriser
    /// the pet uses, so it validates the indexing rather than restating it.
    private static func makeHalfFilledMask(width: Int, height: Int) -> AlphaMask {
        struct HalfFill: PetRenderer {
            func draw(in context: CGContext, size: CGSize, pose: CatPose) {
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height / 2))
            }
        }
        let mask = MaskRaster.make(
            renderer: HalfFill(),
            size: CGSize(width: width, height: height),
            pose: .neutral
        )
        return mask ?? AlphaMask(width: width, height: height, bytes: [UInt8](repeating: 0, count: width * height))
    }

    // MARK: - Bubble helpers

    private struct BubbleInk {
        var textPixels: Int
        var cornerIsClear: Bool
        var tailIsOpaque: Bool
    }

    /// Rasterise a bubble on transparency and report what actually landed.
    private static func bubbleInk(_ content: BubbleContent, size: CGSize) -> BubbleInk {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw -> Void in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            BubbleRenderer.draw(
                in: context,
                size: CGSize(width: width, height: height),
                content: content,
                tailX: size.width / 2,
                tailOnBottom: true
            )
        }

        func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let row = MaskRaster.rowZeroIsBottom ? y : (height - 1 - y)
            let index = (row * width + x) * 4
            return (Int(buffer[index]), Int(buffer[index + 1]), Int(buffer[index + 2]), Int(buffer[index + 3]))
        }

        let rect = BubbleRenderer.textRect(in: size, tailOnBottom: true)
        let background = BubbleRenderer.background(for: content.style).components ?? [0, 0, 0, 1]
        func component(_ index: Int) -> Int {
            let value = background.count >= 3 ? background[index] : background[0]
            return Int((value * 255).rounded())
        }
        let bgR = component(0), bgG = component(1), bgB = component(2)

        var textPixels = 0
        for y in Int(rect.minY)..<min(Int(rect.maxY), height) {
            for x in Int(rect.minX)..<min(Int(rect.maxX), width) {
                let value = pixel(x, y)
                // A glyph is anything that differs from the card background.
                let difference = abs(value.r - bgR) + abs(value.g - bgG) + abs(value.b - bgB)
                if value.a > 40, difference > 60 { textPixels += 1 }
            }
        }

        let corner = pixel(1, height - 2)
        let tail = pixel(width / 2, 1)
        return BubbleInk(textPixels: textPixels, cornerIsClear: corner.a < 16, tailIsOpaque: tail.a > 200)
    }

    // MARK: - Perch inspection

    /// `--windows`: print the perches the scanner can see, in both coordinate
    /// spaces, so the top-left → bottom-left conversion can be eyeballed against
    /// a real desktop.
    ///
    /// Unlike `--selftest`, this one genuinely needs the window server: the
    /// window list and `NSScreen` both come from it.
    static func listPlatforms() -> Int32 {
        _ = NSApplication.shared
        let platforms = WindowScanner.platforms(excludingWindowNumbers: [])
        print("\(platforms.count) window\(platforms.count == 1 ? "" : "s") she can perch on")
        for platform in platforms.sorted(by: { $0.rect.minX < $1.rect.minX }) {
            let rect = platform.rect
            let owner = String(platform.ownerName.prefix(28))
            print(String(
                format: "  #%-8ld %-28@ x[%7.0f %7.0f] top=%7.0f height=%6.0f",
                platform.windowNumber,
                owner as NSString,
                rect.minX, rect.maxX, rect.maxY, rect.height
            ))
        }
        for screen in NSScreen.screens {
            print(String(format: "  screen visible y[%.0f %.0f]", screen.visibleFrame.minY, screen.visibleFrame.maxY))
        }
        return 0
    }

    // MARK: - Offscreen render

    private enum SheetCell {
        case cat(CatPose)
        case bubble(String, BubbleStyle)
    }

    static func renderPNG(to path: String) -> Int32 {
        let columns = 4
        let rows = 6
        let cell = 200
        let width = columns * cell
        let height = rows * cell

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Log.info("could not create render context")
            return 1
        }

        context.setFillColor(CGColor.hex(0xFDF6EC))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        // Faint grid so the poses are easy to compare side by side.
        context.setStrokeColor(CGColor.hex(0xE8DCCB))
        context.setLineWidth(1)
        for column in 1..<columns {
            context.move(to: CGPoint(x: CGFloat(column * cell), y: 0))
            context.addLine(to: CGPoint(x: CGFloat(column * cell), y: CGFloat(height)))
        }
        for row in 1..<rows {
            context.move(to: CGPoint(x: 0, y: CGFloat(row * cell)))
            context.addLine(to: CGPoint(x: CGFloat(width), y: CGFloat(row * cell)))
        }
        context.strokePath()

        let renderer = CatRenderer(palette: .tabby)

        // Grid row 0 is drawn at the *top* of the image: the row index is
        // flipped against CG's bottom-left origin so the printed legend below
        // reads in the same order as the picture.
        let grid: [[SheetCell]] = [
            [
                .bubble("Done. 3 files changed.", .plain),
                .bubble("Watching src/ for changes…", .info),
                .bubble("Build passed.", .success),
                .bubble("Tests failed: 2", .warning),
            ],
            [
                .cat(CatPose()),
                .cat({ var p = CatPose(); p.blink = 0; return p }()),
                .cat({ var p = CatPose(); p.gazeX = -0.8; p.gazeY = -0.4; p.mood = .curious; p.blush = 0.7; p.tailPhase = 1.2; return p }()),
                .cat({ var p = CatPose(); p.facing = -1; p.breathe = 1; return p }()),
            ],
            [
                .cat({ var p = CatPose(); p.mood = .sleepy; p.blink = 0.06; p.breathe = -1; p.tailPhase = 0.4; return p }()),
                .cat({ var p = CatPose(); p.mood = .walking; p.hopOffset = CatPose.RenderLimits.hop; p.tilt = 0.05; p.tailPhase = 2.4; return p }()),
                .cat({ var p = CatPose(); p.mood = .alarmed; p.stretch = 0.9; p.squash = CatPose.RenderLimits.maxSquash; p.gazeY = 0.9; p.tailPhase = 3.1; return p }()),
                .cat({ var p = CatPose(); p.mouthOpen = 1; p.blush = 0.9; p.tailPhase = 0.8; return p }()),
            ],
            [
                .cat({ var p = CatPose(); p.shape = .only(.sit); p.tailPhase = 0.9; return p }()),
                .cat({ var p = CatPose(); p.shape = .only(.loaf); p.tailPhase = 1.6; return p }()),
                .cat({ var p = CatPose(); p.shape = .only(.lie); p.mood = .sleepy; p.blink = 0.05; p.tailPhase = 0.5; return p }()),
                .cat({ var p = CatPose(); p.shape = .only(.stretch); p.tailPhase = 1.1; return p }()),
            ],
            // Mid-settle frames. These are the ones that prove a posture change
            // is an animation and not a hard cut: each cell is a weighted
            // average of two keyframes, drawn by the same code path.
            [
                .cat({ var p = CatPose(); p.shape = .lerp(.only(.stand), .only(.sit), 0.5); p.tailPhase = 1.0; return p }()),
                .cat({ var p = CatPose(); p.shape = .lerp(.only(.sit), .only(.loaf), 0.5); p.tailPhase = 1.4; return p }()),
                .cat({ var p = CatPose(); p.shape = .lerp(.only(.loaf), .only(.lie), 0.5); p.tailPhase = 1.2; return p }()),
                .cat({ var p = CatPose(); p.shape = .lerp(.only(.lie), .only(.stretch), 0.5); p.tailPhase = 1.5; return p }()),
            ],
            // The teleport blink: leaving, gone, and back again.
            [
                .cat({ var p = CatPose(); p.vanish = 0.3; p.tailPhase = 1.0; return p }()),
                .cat({ var p = CatPose(); p.vanish = 0.62; p.tailPhase = 1.0; return p }()),
                .cat({ var p = CatPose(); p.vanish = 0.88; p.tailPhase = 1.0; return p }()),
                .cat({ var p = CatPose(); p.vanish = 0.5; p.tailPhase = 1.0; return p }()),
            ],
        ]

        for (rowIndex, row) in grid.enumerated() {
            for (columnIndex, item) in row.enumerated() {
                context.saveGState()
                context.translateBy(
                    x: CGFloat(columnIndex * cell),
                    y: CGFloat(rows - 1 - rowIndex) * CGFloat(cell)
                )
                context.clip(to: CGRect(x: 0, y: 0, width: CGFloat(cell), height: CGFloat(cell)))
                switch item {
                case .cat(let pose):
                    renderer.draw(in: context, size: CGSize(width: cell, height: cell), pose: pose)
                case .bubble(let text, let style):
                    drawBubbleCell(in: context, cell: CGFloat(cell), text: text, style: style)
                }
                context.restoreGState()
            }
        }

        guard let image = context.makeImage() else {
            Log.info("could not snapshot render context")
            return 1
        }

        let url = URL(fileURLWithPath: path) as CFURL
        guard let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
            Log.info("could not create PNG destination at \(path)")
            return 1
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            Log.info("could not finalise PNG at \(path)")
            return 1
        }

        print("wrote \(width)x\(height) pose sheet to \(path)")
        print("row 1:      say (plain) | info card | success | warning")
        print("row 2:      neutral | blink | curious + blush | facing left")
        print("row 3:      sleepy  | walking | alarmed | talking")
        print("row 4:      sitting | loafing | lying asleep | waking stretch")
        print("row 5:      settling stand->sit | sit->loaf | loaf->lie | lie->stretch")
        print("row 6:      blinking out 30% | 60% | 90% | and back in")
        return 0
    }

    /// A review sheet for the species.
    ///
    /// One page, every animal, standing, loafing and pleased: the point of a
    /// species table is that adding one is a data change, and the only honest way
    /// to check it is to look at all of them together.
    static func renderSpeciesPNG(to path: String) -> Int32 {
        let columns = PetSpecies.allCases.count
        let rows = 3
        let cell = 200
        let width = columns * cell
        let height = rows * cell

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Log.info("could not create render context")
            return 1
        }

        context.setFillColor(CGColor.hex(0xFDF6EC))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.setStrokeColor(CGColor.hex(0xE8DCCB))
        context.setLineWidth(1)
        for column in 1..<columns {
            context.move(to: CGPoint(x: CGFloat(column * cell), y: 0))
            context.addLine(to: CGPoint(x: CGFloat(column * cell), y: CGFloat(height)))
        }
        for row in 1..<rows {
            context.move(to: CGPoint(x: 0, y: CGFloat(row * cell)))
            context.addLine(to: CGPoint(x: CGFloat(width), y: CGFloat(row * cell)))
        }
        context.strokePath()

        let grid: [[SheetCell]] = [
            PetSpecies.allCases.map { species in
                .cat({ var pose = CatPose(); pose.species = species; return pose }())
            },
            PetSpecies.allCases.map { species in
                .cat({ var pose = CatPose(); pose.species = species; pose.shape = .only(.loaf); pose.tailPhase = 1.4; return pose }())
            },
            PetSpecies.allCases.map { species in
                .cat({ var pose = CatPose(); pose.species = species; pose.mood = .happy; pose.tailPhase = 1.1; pose.gazeX = 0.4; return pose }())
            },
        ]

        for (rowIndex, row) in grid.enumerated() {
            for (columnIndex, item) in row.enumerated() {
                context.saveGState()
                context.translateBy(
                    x: CGFloat(columnIndex * cell),
                    y: CGFloat(rows - 1 - rowIndex) * CGFloat(cell)
                )
                context.clip(to: CGRect(x: 0, y: 0, width: CGFloat(cell), height: CGFloat(cell)))
                if case .cat(let pose) = item {
                    CatRenderer(palette: pose.species.defaultCoat.palette)
                        .draw(in: context, size: CGSize(width: cell, height: cell), pose: pose)
                }
                context.restoreGState()
            }
        }

        guard let image = context.makeImage() else {
            Log.info("could not snapshot the species sheet")
            return 1
        }
        let url = URL(fileURLWithPath: path) as CFURL
        guard let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
            Log.info("could not create PNG destination at \(path)")
            return 1
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            Log.info("could not finalise PNG at \(path)")
            return 1
        }

        print("wrote \(width)x\(height) species sheet to \(path)")
        print("row 1: " + PetSpecies.allCases.map { "\($0.name) in \($0.defaultCoat.name)" }.joined(separator: " | "))
        print("row 2: the same five, loafing")
        print("row 3: the same five, pleased")
        return 0
    }

    private static func drawBubbleCell(in context: CGContext, cell: CGFloat, text: String, style: BubbleStyle) {
        let content = BubbleContent(
            id: "sheet",
            text: text,
            style: style,
            streaming: false,
            expiresAt: .infinity
        )
        let size = BubbleRenderer.windowSize(for: content)
        let scale = min(1, (cell - 40) / size.width, (cell - 40) / size.height)

        context.saveGState()
        context.translateBy(
            x: (cell - size.width * scale) / 2,
            y: (cell - size.height * scale) / 2
        )
        context.scaleBy(x: scale, y: scale)
        BubbleRenderer.draw(
            in: context,
            size: size,
            content: content,
            tailX: size.width / 2,
            tailOnBottom: true
        )
        context.restoreGState()
    }
}

/// The poses used to bound the artwork. Deliberately includes values *outside*
/// `CatPose.RenderLimits` so the test proves the renderer's clamping works
/// rather than only proving the limits are the limits.
enum ArtSweep {
    static func oneFactorPoses() -> [CatPose] {
        var poses: [CatPose] = []

        // Tail sway is the largest horizontal excursion in the whole drawing.
        for step in 0..<36 {
            var pose = CatPose()
            pose.tailPhase = Double(step) / 36 * 2 * .pi
            poses.append(pose)
        }

        for twitch in [-0.4, -0.32, -0.16, 0, 0.16, 0.32, 0.4] {
            var pose = CatPose()
            pose.earTwitch = twitch
            poses.append(pose)
        }

        for breathe in [-1.0, 0, 1.0] {
            var pose = CatPose()
            pose.breathe = breathe
            poses.append(pose)
        }

        for blink in [0.0, 0.5, 1.0] {
            var pose = CatPose()
            pose.blink = blink
            poses.append(pose)
        }

        for (gx, gy) in [(1.0, 1.0), (-1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)] {
            var pose = CatPose()
            pose.gazeX = gx
            pose.gazeY = gy
            poses.append(pose)
        }

        for mouth in [0.0, 0.5, 1.0] {
            var pose = CatPose()
            pose.mouthOpen = mouth
            poses.append(pose)
        }

        for blush in [0.0, 1.0] {
            var pose = CatPose()
            pose.blush = blush
            poses.append(pose)
        }

        for mood: CatMood in [.idle, .sleepy, .happy, .curious, .alarmed, .thinking, .walking, .dragged] {
            for facing in [1.0, -1.0] {
                var pose = CatPose()
                pose.mood = mood
                pose.facing = facing
                poses.append(pose)
            }
        }

        return poses
    }

    /// The shapes whose ink bounds the stage: the five keyframes, plus the
    /// mid-settle blends. A posture is drawn as a weighted average of these
    /// keyframes, so a half-finished settle is a shape in its own right and gets
    /// swept like any other.
    static func shapeBlends() -> [CatShapeWeights] {
        CatShape.allCases.map { .only($0) } + [
            .lerp(.only(.stand), .only(.loaf), 0.5),
            .lerp(.only(.sit), .only(.lie), 0.5),
        ]
    }

    /// The full envelope: the deformation corners, plus values deliberately
    /// *outside* `CatPose.RenderLimits` so the test proves the renderer clamps
    /// rather than clips.
    static func poses() -> [CatPose] {
        var poses = oneFactorPoses()
        let limits = CatPose.RenderLimits.self

        // For an affine transform the extremes are attained at the corners of
        // the parameter box, so sampling the corners is enough — the analytic
        // envelope check in `runSelfTest` covers the interior. The shape weights
        // multiply that box, so they are swept alongside it: the resting shapes
        // are lower and wider than the standing cat, and a half-finished settle
        // is a shape in its own right.
        let tails: [Double] = [0, 0.6, 1.2, 1.9, 2.5, 3.2, 4.0, 5.0, 6.0]
        let shapes: [CatShapeWeights] = ArtSweep.shapeBlends()
        for weights in shapes {
            for tail in tails {
                for tilt in [-limits.tilt, limits.tilt] {
                    for stretch in [limits.minStretch, limits.maxStretch] {
                        for squash in [limits.minSquash, limits.maxSquash] {
                            for hop in [0, limits.hop] {
                                for facing in [1.0, -1.0] {
                                    var pose = CatPose()
                                    pose.shape = weights
                                    pose.tailPhase = tail
                                    pose.tilt = tilt
                                    pose.stretch = stretch
                                    pose.squash = squash
                                    pose.hopOffset = hop
                                    pose.facing = facing
                                    pose.earTwitch = limits.earTwitch
                                    poses.append(pose)
                                }
                            }
                        }
                    }
                }
            }
        }

        let beyond: [(tilt: Double, stretch: Double, squash: Double, hop: Double, tail: Double)] = [
            (-0.6, 1.5, 0.5, 12, 1.2),
            (0.6, 1.5, 1.5, 12, 2.0),
            (0.35, 0.5, 1.6, 9, 4.0),
            (-0.2, 1.3, 0.7, 0, 5.5),
        ]
        for extreme in beyond {
            for facing in [1.0, -1.0] {
                var pose = CatPose()
                pose.tilt = extreme.tilt
                pose.stretch = extreme.stretch
                pose.squash = extreme.squash
                pose.hopOffset = extreme.hop
                pose.tailPhase = extreme.tail
                pose.facing = facing
                poses.append(pose)
            }
        }

        // The blink, which is the one pose parameter the deformation limits do
        // not cover: it has to reach zero.
        poses.append(contentsOf: blinkPoses())
        return poses
    }

    /// Every step of the teleport blink, both ways round.
    static func blinkPoses() -> [CatPose] {
        var poses: [CatPose] = []
        for step in 0...12 {
            let vanish = Double(step) / 12
            for facing in [1.0, -1.0] {
                var pose = CatPose()
                pose.vanish = vanish
                pose.facing = facing
                poses.append(pose)
            }
        }
        return poses
    }
}
