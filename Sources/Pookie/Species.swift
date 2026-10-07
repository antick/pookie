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

    var name: String {
        switch self {
        case .cat: return "Cat"
        case .bunny: return "Bunny"
        case .puppy: return "Puppy"
        case .fox: return "Fox"
        case .panda: return "Panda"
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
            // Slim, sharp ears, and a tail half again as thick as a cat's.
            return SpeciesTraits(
                scale: 0.92,
                bodyWidth: 0.95,
                bodyHeight: 0.98,
                headScale: 0.98,
                muzzle: 0.95,
                ears: .pointed,
                earLift: 1.2,
                tail: .curve,
                tailScale: 0.95,
                tailWidth: 1.3,
                tailLift: 5,
                tailTuft: true,
                stripes: false
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
        }
    }
}

/// How an animal's ears are drawn.
enum EarStyle {
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
    /// The cat's curve, stroked; also the fox's, with `tailWidth` and a tuft.
    case curve
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
}
