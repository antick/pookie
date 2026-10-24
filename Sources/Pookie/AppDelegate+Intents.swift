import AppKit

extension AppDelegate {
    /// The control socket: `PROTOCOL.md` §1's transport, wired to the behaviour that
    /// already exists in-process.
    ///
    /// The verbs that have an in-process implementation are mapped here; `emote` and
    /// `face` do not exist yet and answer `unsupported`, which is what that error code
    /// is for. A pet with no control socket is not a broken pet, so a failure to bind
    /// is logged and survived rather than fatal.
    func installControlServer() {
        let server = ControlServer()
        server.petNames = { [weak self] in
            (self?.cohort?.collection ?? []).filter(\.onDesk).map(\.name)
        }
        server.handler = { [weak self] intent in
            self?.submit(intent) ?? .refused(intent.id, .unsupported)
        }
        do {
            try server.start()
        } catch {
            Log.info("control: not listening — \(error)")
        }
        controlServer = server
        // The pet's own events, out to whoever subscribed.
        cohort?.onEvent = { [weak server] event, payload in
            let pet = payload["pet"] as? String ?? "pookie"
            var data = payload
            data.removeValue(forKey: "pet")
            server?.emit(event, pet: pet, data: data)
        }
    }

    /// Offer an intent to the stack, then do what the stack decided.
    ///
    /// Every decision is logged with a reason (M2 criterion 7), because "why did my
    /// line not appear?" is the question a producer actually asks.
    func submit(_ intent: Intent) -> IntentAck {
        let now = Date().timeIntervalSince1970 * 1000
        var entry = ActionStack.Entry(
            intent: intent,
            priority: intent.priority,
            verb: intent.verb,
            at: now
        )
        // How long this action will hold the stack, if it holds one at all. A `say`
        // holds it for the bubble's life; an `emote` for its own hold; everything else
        // completes at once.
        switch intent.verb {
        case .say, .bubbleShow:
            let duration = (intent.args["durationMs"] as? Double).map { $0 / 1000 } ?? 3.5
            entry.deadline = now + duration * 1000
        case .emote:
            let hold = (intent.args["durationMs"] as? Double) ?? 2_000
            entry.deadline = now + hold
        case .lookAt, .face:
            entry.deadline = now + ((intent.args["holdMs"] as? Double) ?? 2_000)
        default:
            entry.deadline = .infinity
        }

        switch actionStack.submit(entry, now: now) {
        case .started(let preempted):
            if let preempted {
                Log.info("control: \(intent.verb.rawValue) (priority \(entry.priority)) preempted \(preempted.rawValue)")
            }
            return perform(intent)

        case .queued(let behind):
            Log.info("control: \(intent.verb.rawValue) (priority \(entry.priority)) queued behind \(behind.rawValue)")
            // The protocol has a word for this, and the ack should use it.
            return IntentAck(id: intent.id, ok: true, accepted: "queued", error: nil, etaMs: nil)

        case .dropped(let reason):
            Log.info("control: \(intent.verb.rawValue) dropped — \(reason)")
            return reason == "expired"
                ? .refused(intent.id, .expired)
                : .refused(intent.id, .rateLimited)
        }
    }

    /// One intent, mapped onto behaviour that already exists.
    func perform(_ intent: Intent) -> IntentAck {
        guard let cohort else { return .refused(intent.id, .unknownPet) }
        switch intent.verb {
        case .say:
            guard let text = intent.args["text"] as? String else {
                return .refused(intent.id, .badArgs)
            }
            let style = (intent.args["style"] as? String).flatMap(BubbleStyle.init(rawValue:)) ?? .plain
            // Through the same per-producer budget the notification bridge uses: the
            // protocol names the producer, so a chatty client is limited like any
            // other.
            let producer = (intent.args["producer"] as? String) ?? "socket"
            _ = cohort.say(text, style: style, from: producer)
            return .started(intent.id)

        case .hide, .show:
            cohort.setHidden(intent.verb == .hide)
            return .started(intent.id)

        case .spawn:
            guard cohort.spawn() != nil else { return .refused(intent.id, .capacity) }
            return .started(intent.id)

        case .despawn:
            guard cohort.removePet(at: cohort.count - 1) else {
                return .refused(intent.id, .capacity)
            }
            return .started(intent.id)

        case .moveTo:
            guard let target = moveTarget(for: intent) else {
                return .refused(intent.id, .badArgs)
            }
            for pet in cohort.pets { pet.motion.move(to: target, animated: true) }
            return .started(intent.id)

        case .face:
            guard let raw = intent.args["direction"] as? String else {
                return .refused(intent.id, .badArgs)
            }
            let hold = ((intent.args["holdMs"] as? Double) ?? 0) / 1000
            let direction: Double?
            switch raw {
            case "left": direction = -1
            case "right": direction = 1
            case "cursor":
                guard let cursor = cohort.spokespet?.motion.cursor else {
                    return .refused(intent.id, .badArgs)
                }
                let centre = cohort.spokespet?.motion.origin.x ?? 0
                direction = cursor.x >= centre ? 1 : -1
            case "front-window":
                // Face the window she is working in: the scanner already knows which
                // one that is.
                guard let target = frontWindowPoint(),
                      let origin = cohort.spokespet?.motion.origin else {
                    return .refused(intent.id, .unsupported)
                }
                direction = target.x >= origin.x ? 1 : -1
            default:
                return .refused(intent.id, .badArgs)
            }
            for pet in cohort.pets { pet.motion.holdFacing(direction, seconds: hold) }
            return .started(intent.id)

        case .state:
            guard let raw = intent.args["name"] as? String,
                  let name = IntentMapping.StateName(rawValue: raw)
            else {
                return .refused(intent.id, .badArgs)
            }
            let profile = IntentMapping.profile(for: name)
            // `hidden` is the one mode that changes what is on screen rather than how
            // she behaves.
            cohort.setHidden(profile.hides)
            for pet in cohort.pets { pet.motion.applyState(name == .idle ? nil : profile) }
            Log.info("state -> \(name.rawValue)")
            return .started(intent.id)

        case .emote:
            guard let raw = intent.args["name"] as? String,
                  let emote = IntentMapping.Emote(rawValue: raw)
            else {
                return .refused(intent.id, .badArgs)
            }
            let seconds = ((intent.args["durationMs"] as? Double) ?? 2_000) / 1000
            guard cohort.spokespet?.motion.applyEmote(emote, seconds: seconds) == true else {
                // `sparkle` and `sweat` need an effect this renderer does not have.
                // Saying so is better than faking them as a mood that means something
                // else.
                return .refused(intent.id, .unsupported)
            }
            if let line = emote.line {
                _ = cohort.say(line, from: "socket")
            }
            return .started(intent.id)

        case .lookAt:
            guard let target = lookTarget(for: intent) else {
                return .refused(intent.id, .badArgs)
            }
            let hold = ((intent.args["holdMs"] as? Double) ?? 2_000) / 1000
            for pet in cohort.pets { pet.motion.holdGaze(at: target, seconds: hold) }
            return .started(intent.id)

        case .bubbleShow:
            guard let text = intent.args["text"] as? String else {
                return .refused(intent.id, .badArgs)
            }
            let style = (intent.args["style"] as? String).flatMap(BubbleStyle.init(rawValue:)) ?? .plain
            // Streaming on purpose: `bubble.show` opens a bubble that `bubble.append`
            // grows, which is what a token stream needs.
            let outcome = cohort.spokespet?.say(
                text,
                style: style,
                duration: (intent.args["durationMs"] as? Double).map { $0 / 1000 },
                streaming: true,
                from: "socket"
            )
            return outcome == .started || outcome == .replaced
                ? .started(intent.id)
                : .refused(intent.id, .rateLimited)

        case .bubbleAppend:
            guard let delta = intent.args["text"] as? String else {
                return .refused(intent.id, .badArgs)
            }
            let final = (intent.args["final"] as? Bool) ?? false
            let outcome = cohort.spokespet?.appendToBubble(delta, final: final)
            return outcome == .started || outcome == .replaced ? .started(intent.id) : .refused(intent.id, .badArgs)

        case .bubbleHide:
            cohort.hideBubble()
            return .started(intent.id)

        case .petOn:
            // A subscription is per *connection*, so it belongs to the transport rather
            // than to the behaviour layer. Answered by the server.
            return .refused(intent.id, .unsupported)
        }
    }

    /// Where a `lookAt` wants her eyes, in AppKit's coordinates.
    func lookTarget(for intent: Intent) -> CGPoint? {
        if let raw = intent.args["target"] as? String {
            switch raw {
            case "cursor": return NSEvent.mouseLocation
            case "front-window": return frontWindowPoint()
            case "menubar":
                guard let screen = NSScreen.screens.first else { return nil }
                return CGPoint(x: screen.frame.midX, y: screen.frame.maxY - 8)
            default: return nil
            }
        }
        if let raw = intent.args["anchor"] as? String,
           let anchor = IntentMapping.Anchor(rawValue: raw) {
            guard let screen = NSScreen.screens.first else { return nil }
            guard let point = IntentMapping.point(
                for: anchor,
                region: screen.visibleFrame,
                displayHeight: screen.frame.height,
                petSize: AppConfig.shared.petSize,
                cursor: NSEvent.mouseLocation
            ) else { return nil }
            return anchor == .cursor
                ? point
                : IntentMapping.toAppKit(point, mainDisplayHeight: screen.frame.height)
        }
        guard let x = intent.args["x"] as? Double, let y = intent.args["y"] as? Double else {
            return nil
        }
        let height = NSScreen.screens.first?.frame.height ?? 900
        return IntentMapping.toAppKit(CGPoint(x: x, y: y), mainDisplayHeight: height)
    }

    /// The frontmost window's top-right corner, from the platforms the perch pump
    /// already scans.
    ///
    /// The protocol notes that this "may require Screen Recording". It does not here:
    /// `CGWindowListCopyWindowInfo` reports geometry with no permission, which is the
    /// same fact perching works on. Nil when there is no window to point at, which the
    /// caller turns into a refusal rather than a guess.
    func frontWindowPoint() -> CGPoint? {
        guard let motion = cohort?.spokespet?.motion,
              let owner = motion.preferredPlatformOwner,
              let platform = motion.platforms.first(where: { $0.ownerName == owner })
        else { return nil }
        return CGPoint(x: platform.rect.maxX, y: platform.top)
    }

    /// Where a `moveTo` wants her, in AppKit's coordinates.
    ///
    /// The protocol speaks Core Graphics global display space — origin top-left, `y`
    /// down — which is the convention `CGWindowListCopyWindowInfo` uses and therefore
    /// the one that keeps producer code boring. AppKit is bottom-left, so this is the
    /// single place the flip happens.
    func moveTarget(for intent: Intent) -> CGPoint? {
        let screens = NSScreen.screens
        let mainHeight = screens.first?.frame.maxY ?? 0

        if let raw = intent.args["anchor"] as? String,
           let anchor = IntentMapping.Anchor(rawValue: raw) {
            // The one anchor that is not a coordinate conversion: it is the frontmost
            // window's edge, which the scanner already knows.
            if anchor == .frontWindowEdge {
                guard let edge = frontWindowPoint() else { return nil }
                return CGPoint(
                    x: edge.x - AppConfig.shared.petSize.width,
                    y: edge.y
                )
            }
            let region = screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            guard let point = IntentMapping.point(
                for: anchor,
                region: region,
                displayHeight: screens.first?.frame.height ?? 900,
                petSize: AppConfig.shared.petSize,
                cursor: NSEvent.mouseLocation
            ) else { return nil }
            // Anchors are already resolved into the protocol's space by `point(for:)`;
            // the cursor is handed in from AppKit, so it comes back unchanged and is
            // the one case that does not need the flip.
            return anchor == .cursor ? point : IntentMapping.toAppKit(point, mainDisplayHeight: mainHeight)
        }

        guard let x = intent.args["x"] as? Double, let y = intent.args["y"] as? Double else {
            return nil
        }
        return IntentMapping.toAppKit(CGPoint(x: x, y: y), mainDisplayHeight: mainHeight)
    }

}
