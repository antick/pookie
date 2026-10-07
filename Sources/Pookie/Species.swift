import CoreGraphics

/// What kind of animal a pet is.
///
/// A species is a table, not a second renderer: every animal is drawn from the
/// same skeleton, wearing different proportions and different appendages, so all
/// of the behaviour work — perching, jumping, loafing, stretching, blinking,
/// playing — belongs to all of them for free. The one rule the table has to
/// respect is the ground line: everything scales about `CatGeometry.feetY`, so no
/// species floats.
enum PetSpecies: String, CaseIterable {
    case cat
    case bunny
    case puppy
    case fox
    case panda
    case duckling
    case bear
    case hamster
    case penguin
    case raccoon
    case corgi
    case squirrel
    case redPanda
    case koala
    case otter
    case capybara
    case chick
    case robin
    case owl
    case hedgehog
    case axolotl
    case frog

    var name: String {
        switch self {
        case .cat: return "Cat"
        case .bunny: return "Bunny"
        case .puppy: return "Puppy"
        case .fox: return "Fox"
        case .panda: return "Panda"
        case .duckling: return "Duckling"
        case .bear: return "Bear"
        case .hamster: return "Hamster"
        case .penguin: return "Penguin"
        case .raccoon: return "Raccoon"
        case .corgi: return "Corgi"
        case .squirrel: return "Squirrel"
        case .redPanda: return "Red panda"
        case .koala: return "Koala"
        case .otter: return "Otter"
        case .capybara: return "Capybara"
        case .chick: return "Chick"
        case .robin: return "Robin"
        case .owl: return "Owl"
        case .hedgehog: return "Hedgehog"
        case .axolotl: return "Axolotl"
        case .frog: return "Frog"
        }
    }

    /// What a new pookie of this kind is called until the human renames it.
    var defaultName: String {
        switch self {
        case .cat: return "Pookie"
        case .bunny: return "Clover"
        case .puppy: return "Biscuit"
        case .fox: return "Ember"
        case .panda: return "Mochi"
        case .duckling: return "Puddle"
        case .bear: return "Barnaby"
        case .hamster: return "Peanut"
        case .penguin: return "Waddles"
        case .raccoon: return "Bandit"
        case .corgi: return "Shortbread"
        case .squirrel: return "Hazel"
        case .redPanda: return "Rusty"
        case .koala: return "Gumleaf"
        case .otter: return "Pebble"
        case .capybara: return "Biscuit"
        case .chick: return "Pip"
        case .robin: return "Berry"
        case .owl: return "Sage"
        case .hedgehog: return "Bramble"
        case .axolotl: return "Bloom"
        case .frog: return "Pond"
        }
    }

    /// The coat that makes this animal look like itself, before the user picks a
    /// different one on purpose.
    var defaultCoat: CatSkin {
        switch self {
        case .cat: return .tabby
        case .bunny: return .snow
        case .puppy: return .chocolate
        case .fox: return .ginger
        case .panda: return .panda
        case .duckling: return .duckling
        case .bear: return .cocoa
        case .hamster: return .hazel
        // A penguin is the panda's palette: white fur with black points.
        case .penguin: return .panda
        case .raccoon: return .grey
        case .corgi: return .ginger
        case .squirrel: return .chocolate
        case .redPanda: return .ginger
        case .koala: return .grey
        case .otter: return .chocolate
        case .capybara: return .chocolate
        case .chick: return .duckling
        case .robin: return .robin
        case .owl: return .cocoa
        case .hedgehog: return .chocolate
        case .axolotl: return .blossom
        case .frog: return .moss
        }
    }

    var traits: SpeciesTraits {
        switch self {
        case .cat:
            return SpeciesTraits()
        case .bunny:
            // A small creature with tall ears: the whole body is scaled down so
            // the ears can be long without leaving the stage the cat defined.
            return SpeciesTraits(
                scale: 0.82,
                bodyWidth: 1.08,
                bodyHeight: 1.0,
                headScale: 1.0,
                muzzle: 0.78,
                ears: .long,
                earLift: 1.15,
                tail: .puff,
                tailScale: 0.8,
                whiskers: false,
                stripes: false
            )
        case .puppy:
            // Bigger head, wider body, big floppy ears that hang rather than
            // stand: no extra height, all of the softness.
            return SpeciesTraits(
                scale: 0.95,
                bodyWidth: 1.08,
                bodyHeight: 1.0,
                headScale: 1.05,
                muzzle: 1.25,
                ears: .floppy,
                earLift: 1.0,
                tail: .curl,
                tailScale: 0.85,
                whiskers: false,
                stripes: false
            )
        case .fox:
            // A fox is not a cat with pointed ears: the snout is narrow and
            // white-tipped, there are dark socks on all four legs, and the tail is
            // a brush with a pale end. The ears sit wider apart and lower than a
            // cat's, which is most of what stops the two reading the same.
            return SpeciesTraits(
                scale: 0.9,
                bodyWidth: 0.84,
                bodyHeight: 0.94,
                headScale: 0.93,
                muzzle: 1.5,
                ears: .pointed,
                earLift: 1.15,
                tail: .brush,
                tailScale: 1.05,
                tailWidth: 1.15,
                tailLift: 6,
                tailTuft: true,
                stripes: false,
                socks: true,
                cheekRuff: true,
                paleEarInner: true
            )
        case .panda:
            // A round body, a small head, small ears on top, and the patches:
            // a panda is read entirely from its markings, so the dark parts use
            // `furDark` — the coat supplies the black.
            return SpeciesTraits(
                scale: 0.95,
                bodyWidth: 1.22,
                bodyHeight: 1.1,
                headScale: 0.95,
                muzzle: 1.0,
                ears: .round,
                earLift: 1.0,
                tail: .puff,
                tailScale: 0.75,
                whiskers: false,
                stripes: false,
                eyePatches: true,
                darkLimbs: true
            )
        case .duckling:
            // A bird: no ears, a bill, wings instead of forelegs, and a flat
            // little body that reads as a duckling from across the room.
            return SpeciesTraits(
                scale: 0.7,
                bodyWidth: 1.15,
                bodyHeight: 1.05,
                headScale: 1.15,
                muzzle: 0.6,
                ears: .none,
                tail: .puff,
                tailScale: 0.55,
                whiskers: false,
                stripes: false,
                bill: true,
                wings: true,
                legs: .webbed
            )
        case .bear:
            // A cub: a big round body, small round ears, a broad muzzle and no
            // neck to speak of.
            return SpeciesTraits(
                scale: 1.0,
                bodyWidth: 1.3,
                bodyHeight: 1.12,
                headScale: 0.92,
                muzzle: 1.3,
                ears: .round,
                earLift: 0.8,
                tail: .puff,
                tailScale: 0.5,
                whiskers: false,
                stripes: false
            )
        case .hamster:
            // Small and round with button ears and fat cheeks, and the shortest
            // legs of anything here.
            return SpeciesTraits(
                scale: 0.62,
                bodyWidth: 1.35,
                bodyHeight: 1.05,
                headScale: 1.05,
                muzzle: 1.1,
                ears: .round,
                earLift: 0.7,
                tail: .puff,
                tailScale: 0.35,
                whiskers: true,
                stripes: false,
                cheeks: true
            )
        case .penguin:
            // A bird built like a bottle: no ears, a small bill, flippers, and
            // the panda's palette doing the black-and-white for free.
            return SpeciesTraits(
                scale: 0.82,
                bodyWidth: 1.1,
                bodyHeight: 1.18,
                headScale: 0.95,
                muzzle: 0.55,
                ears: .none,
                tail: .puff,
                tailScale: 0.3,
                whiskers: false,
                stripes: false,
                bill: true,
                wings: true,
                legs: .webbed,
                slides: true
            )
        case .raccoon:
            // Round ears, a ringed brush of a tail, and the mask that names it.
            return SpeciesTraits(
                scale: 0.9,
                bodyWidth: 1.05,
                bodyHeight: 1.0,
                headScale: 1.0,
                muzzle: 1.15,
                ears: .round,
                earLift: 0.9,
                tail: .brush,
                tailScale: 0.95,
                tailWidth: 1.05,
                tailLift: 5,
                whiskers: true,
                stripes: false,
                ringedTail: true
            )
        case .corgi:
            // Big ears, no tail worth the name, and the shortest legs in the
            // catalogue — which is the whole joke of a corgi.
            return SpeciesTraits(
                scale: 0.72,
                bodyWidth: 1.2,
                bodyHeight: 0.95,
                headScale: 1.1,
                muzzle: 1.3,
                ears: .pointed,
                earLift: 0.9,
                tail: .puff,
                tailScale: 0.35,
                whiskers: false,
                stripes: false,
                legs: .short
            )
        case .squirrel:
            // Tufted ears, a small body, and a brush tail bigger than the animal.
            return SpeciesTraits(
                scale: 0.62,
                bodyWidth: 0.95,
                bodyHeight: 1.0,
                headScale: 1.05,
                muzzle: 1.0,
                ears: .pointed,
                earLift: 0.8,
                tail: .brush,
                tailScale: 1.1,
                tailWidth: 1.1,
                tailLift: 8,
                whiskers: true,
                stripes: false
            )
        case .redPanda:
            // A raccoon in rust: ringed brush, round ears, and a face mask.
            return SpeciesTraits(
                scale: 0.82,
                bodyWidth: 1.1,
                bodyHeight: 1.0,
                headScale: 1.0,
                muzzle: 1.05,
                ears: .round,
                earLift: 0.95,
                tail: .brush,
                tailScale: 1.0,
                tailWidth: 1.1,
                tailLift: 6,
                whiskers: true,
                stripes: false,
                ringedTail: true
            )
        case .koala:
            // All ears and nose: the fluffiest ears here, on a small round head.
            return SpeciesTraits(
                scale: 0.85,
                bodyWidth: 1.1,
                bodyHeight: 1.0,
                headScale: 1.05,
                muzzle: 1.5,
                ears: .round,
                earLift: 1.7,
                tail: .puff,
                tailScale: 0.3,
                whiskers: false,
                stripes: false
            )
        case .otter:
            // Long and low, with a thick tail and a pale muzzle.
            return SpeciesTraits(
                scale: 0.78,
                bodyWidth: 1.3,
                bodyHeight: 0.85,
                headScale: 1.0,
                muzzle: 1.3,
                ears: .round,
                earLift: 0.5,
                tail: .brush,
                tailScale: 0.9,
                tailWidth: 1.2,
                tailLift: 3,
                whiskers: true,
                stripes: false
            )
        case .capybara:
            // A loaf with legs: the biggest body and the smallest ears here.
            return SpeciesTraits(
                scale: 0.95,
                bodyWidth: 1.45,
                bodyHeight: 1.15,
                headScale: 0.9,
                muzzle: 1.35,
                ears: .round,
                earLift: 0.45,
                tail: .puff,
                tailScale: 0.2,
                whiskers: true,
                stripes: false
            )
        case .chick:
            // The smallest bird: round, yellow, and all fluff.
            return SpeciesTraits(
                scale: 0.5,
                bodyWidth: 1.1,
                bodyHeight: 1.1,
                headScale: 1.1,
                muzzle: 0.5,
                ears: .none,
                tail: .puff,
                tailScale: 0.3,
                whiskers: false,
                stripes: false,
                bill: true,
                wings: true,
                legs: .short
            )
        case .robin:
            // A round bird with a red breast and a neat bill.
            return SpeciesTraits(
                scale: 0.62,
                bodyWidth: 1.15,
                bodyHeight: 1.05,
                headScale: 1.05,
                muzzle: 0.6,
                ears: .none,
                tail: .puff,
                tailScale: 0.45,
                whiskers: false,
                stripes: false,
                bill: true,
                wings: true,
                legs: .short
            )
        case .owl:
            // Enormous eyes, tufts, and a hooked bill: the only bird here that
            // does not look like it would fit in a teacup.
            return SpeciesTraits(
                scale: 0.85,
                bodyWidth: 1.2,
                bodyHeight: 1.05,
                headScale: 1.25,
                muzzle: 0.7,
                ears: .pointed,
                earLift: 0.5,
                tail: .puff,
                tailScale: 0.4,
                whiskers: false,
                stripes: false,
                bill: true,
                wings: true,
                eyeScale: 1.7
            )
        case .hedgehog:
            // A small round animal wearing a whole back of spikes.
            return SpeciesTraits(
                scale: 0.66,
                bodyWidth: 1.25,
                bodyHeight: 1.05,
                headScale: 0.95,
                muzzle: 1.1,
                ears: .round,
                earLift: 0.5,
                tail: .puff,
                tailScale: 0.2,
                whiskers: true,
                stripes: false,
                spikes: true
            )
        case .axolotl:
            // A salamander: smooth, no ears, three frills a side, and a fin for a
            // tail.
            return SpeciesTraits(
                scale: 0.72,
                bodyWidth: 1.1,
                bodyHeight: 0.95,
                headScale: 1.15,
                muzzle: 1.05,
                ears: .none,
                tail: .brush,
                tailScale: 0.9,
                tailWidth: 0.8,
                tailLift: 4,
                whiskers: false,
                stripes: false,
                gills: true
            )
        case .frog:
            // Eyes on top of the head and a mouth as wide as the head is: a frog
            // is read entirely from those two things.
            return SpeciesTraits(
                scale: 0.62,
                bodyWidth: 1.3,
                bodyHeight: 0.95,
                headScale: 1.2,
                muzzle: 1.5,
                ears: .none,
                tail: .puff,
                tailScale: 0.2,
                whiskers: false,
                stripes: false,
                legs: .short,
                eyeLift: 0.5
            )
        }
    }
}

/// How an animal's ears are drawn.
enum EarStyle {
    /// No ears at all — a bird has a smooth head.
    case none
    /// The original: a triangle whose tip lifts above the skull.
    case cat
    /// Tall rounded ears that stand up — a bunny.
    case long
    /// Rounded flaps hanging down the sides of the head — a puppy.
    case floppy
    /// Taller, wider triangles with a dark tip — a fox.
    case pointed
    /// Small circles sitting on top of the head — a panda or a bear.
    case round
}

/// How an animal's tail is drawn.
enum TailStyle {
    /// The cat's curve, stroked.
    case curve
    /// A fox's brush: the same spine, but the tail itself is a filled shape —
    /// a fat fluff around the middle with a pale tip. A stroked curve, however
    /// thick, is still a cat's tail.
    case brush
    /// A ball of fluff at the rump — a bunny or a panda.
    case puff
    /// A short tail curling upward — a puppy.
    case curl
}

/// One species' proportions and appendages.
///
/// Defaults are the cat, so `.cat` is an empty table and the M0 artwork is
/// unchanged by any of this.
struct SpeciesTraits {
    /// Overall size, applied about the ground line. A bunny is a small animal
    /// with long ears rather than a cat with a hat on.
    var scale: CGFloat = 1
    var bodyWidth: CGFloat = 1
    var bodyHeight: CGFloat = 1
    /// Head radius, on top of `scale`.
    var headScale: CGFloat = 1
    /// Muzzle size, on top of `scale`.
    var muzzle: CGFloat = 1
    var ears: EarStyle = .cat
    /// Ear length, on top of `scale`.
    var earLift: CGFloat = 1
    var tail: TailStyle = .curve
    /// Tail length, on top of `scale`.
    var tailScale: CGFloat = 1
    /// Tail thickness, on top of `scale`.
    var tailWidth: CGFloat = 1
    /// Design units to lift the tail by. A thick tail is a *tall* tail: a
    /// stroked curve half a brush wider than a cat's would otherwise hang below
    /// the ground line it is resting on.
    var tailLift: CGFloat = 0
    /// A lighter tip on the tail — the fox's brush.
    var tailTuft: Bool = false
    var whiskers: Bool = true
    var stripes: Bool = true
    /// Dark patches around the eyes, drawn in `furDark`.
    var eyePatches: Bool = false
    /// Paws and ear backs in `furDark` rather than `belly` — a panda's black
    /// limbs.
    var darkLimbs: Bool = false
    /// Dark feet: the fox's socks.
    var socks: Bool = false
    /// A pale ruff around the jaw and chest, which is how a fox is told from a
    /// cat at a glance.
    var cheekRuff: Bool = false
    /// Pale ear inners rather than pink: a fox, not a cat.
    var paleEarInner: Bool = false
    /// A bill instead of a muzzle and nose — a duckling.
    var bill: Bool = false
    /// Wings instead of forelegs, which also flap.
    var wings: Bool = false
    /// Fat cheeks, drawn as two puffs either side of the muzzle — a hamster.
    var cheeks: Bool = false
    /// How the feet are drawn.
    var legs: LegStyle = .paws
    /// Rings down the tail, without the user choosing the marking: a raccoon's
    /// tail is not a coat option.
    var ringedTail: Bool = false
    /// A back of spikes — a hedgehog.
    var spikes: Bool = false
    /// Three frills a side — an axolotl.
    var gills: Bool = false
    /// Eyes lifted above the skull line, as a fraction of the head radius: a
    /// frog's eyes are on top of its head.
    var eyeLift: CGFloat = 0
    /// Eye size, on top of the head scale: an owl is mostly eyes.
    var eyeScale: CGFloat = 1
    /// Belly-slides along the floor when it wants to move fast, rather than
    /// waddling: a penguin's other gait.
    var slides: Bool = false
}

/// How an animal's feet are drawn.
enum LegStyle {
    /// Rounded paws, with a hint of toes.
    case paws
    /// Flat webbed feet with a splay — a duckling.
    case webbed
    /// Very short legs: a corgi, a chick, a frog.
    case short
}
