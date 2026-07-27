import Foundation

/// Ground-truth BWW/BMW embellishment token -> grace-note-pitch-sequence
/// table, transcribed from Ensemble's (thisisensemble.com) own `editor.js`
/// (`embellishmentShortname`/`embellishmentNotes` arrays) — the app's actual
/// internal vocabulary, not a secondary or approximated source. This
/// replaces an earlier hand-derived approximation (built from a 1990s
/// `bww2tex` lexer) that got several real ornaments wrong — e.g. taorluath
/// and crunluath were missing grace notes, and throw-on-D had the wrong
/// pitches. Given a real tune file, prefer trusting this table over deriving
/// new mappings by ear.
///
/// Letter notation: lowercase g/a/b/c/d/e/f = Low G, Low A, B, C, D, E, F;
/// uppercase G/A = High G, High A. `X` is a rendering-only placeholder in
/// the source (an abbreviated-notation glyph for certain "above the line"
/// variants) and isn't a playable pitch, so it's skipped when decoding.
enum BWWEmbellishmentTable {

    /// token (lowercase) -> grace letters in play order.
    private static let graceLetters: [String: String] = [
        // Grace Notes
        "ag": "a", "bg": "b", "cg": "c", "dg": "d", "eg": "e", "fg": "f", "gg": "G", "tg": "A",

        // Strikes
        "gstla": "Gag", "gstb": "Gbg", "gstc": "Gcg", "gstd": "Gdg", "lgstd": "Gdc",
        "gste": "Gea", "gstf": "Gfe",
        "tstla": "Aag", "tstb": "Abg", "tstc": "Acg", "tstd": "Adg", "ltstd": "Adc",
        "tste": "Aea", "tstf": "Afe", "tsthg": "AGf",
        "hstla": "ag", "hstb": "bg", "hstc": "cg", "hstd": "dg", "lhstd": "dc",
        "hste": "ea", "hstf": "fe", "hsthg": "Gf",
        "strlg": "g", "strla": "a", "strb": "b", "strc": "c", "strd": "d", "stre": "e",
        "strf": "f", "strhg": "G",

        // Doublings / Thumb / Half
        "dblg": "Ggd", "dbla": "Gad", "dbb": "Gbd", "dbc": "Gcd", "dbd": "Gde",
        "dbe": "Gef", "dbf": "GfG", "dbhg": "Gf", "dbha": "AG",
        "tdblg": "Agd", "tdbla": "Aad", "tdbb": "Abd", "tdbc": "Acd", "tdbd": "Ade",
        "tdbe": "Aef", "tdbf": "AfG",
        "hdblg": "gd", "hdbla": "ad", "hdbb": "bd", "hdbc": "cd", "hdbd": "de",
        "hdbe": "ef", "hdbf": "fG",

        // Grips
        "grp": "gdg", "hgrp": "dg", "grpb": "gbg",

        // G / Thumb / Half Grace Note Grips
        "ggrpla": "Gagdg", "ggrpb": "Gbgdg", "ggrpc": "Gcgdg", "ggrpd": "Gdgdg",
        "ggrpdb": "Gdgbg", "ggrpe": "Gegdg", "ggrpf": "Gfgfg",
        "tgrpla": "Aagdg", "tgrpb": "Abgdg", "tgrpc": "Acgdg", "tgrpd": "Adgdg",
        "tgrpdb": "Adgbg", "tgrpe": "Aegdg", "tgrpf": "Afgfg", "tgrphg": "AGgfg",
        "hgrpla": "agdg", "hgrpb": "bgdg", "hgrpc": "cgdg", "hgrpd": "dgdg",
        "hgrpdb": "dgbg", "hgrpe": "egdg", "hgrpf": "fgfg", "hgrphg": "Ggdg", "hgrpha": "Agdg",

        // Taorluaths
        "tar": "gdge", "tarb": "gbge", "htar": "dge", "htarla": "dae", "htarlg": "dge",
        "pt": "Xgdgea", "ptb": "Xgbgea", "phtla": "Xdae",

        // Closed Taorluaths
        "tarbrea": "gdge", "tarbbrea": "gbge", "htarlabrea": "dge",
        "ptbrea": "dge", "ptbbrea": "gdge", "phtlabrea": "gbge",

        // Taorluath a Machs
        "ptmb": "gdge", "ptmc": "gdge", "ptmd": "gdc",

        // Birls
        "brl": "gag", "abr": "agag", "gbr": "Gagag", "tbr": "Aagag",

        // Throws
        "thrd": "gdc", "hvthrd": "gdgc", "hthrd": "dc", "hhvthrd": "dgc",

        // Bublys
        "bubly": "gdgcg", "hbubly": "dgcg",

        // Peles / Thumb / Half
        "pella": "Gaeag", "pelb": "Gbebg", "pelc": "Gcecg", "peld": "Gdedg",
        "lpeld": "Gdedc", "pele": "Gefea", "pelf": "GfGfe",
        "tpella": "Aaeag", "tpelb": "Abebg", "tpelc": "Acecg", "tpeld": "Adedc",
        "tpele": "Aefea", "tpelf": "AfGfe", "tpelhg": "AGAGf",
        "hpella": "aeag", "hpelb": "bebg", "hpelc": "cecg", "hpeld": "dedg",
        "lhpeld": "dedc", "hpele": "efea", "hpelf": "fGfe", "hpelhg": "GAGf",

        // Double Strikes (2 repeats)
        "st2la": "gag", "st2b": "gbg", "st2c": "gcg", "st2d": "gdg", "lst2d": "cdc",
        "st2e": "geg", "st2f": "efe", "st2hg": "fGf", "st2ha": "GAG",
        "gst2la": "Gagag", "gst2b": "Gbgbg", "gst2c": "Gcgcg", "gst2d": "Gdgdg",
        "lgst2d": "Gdcdc", "gst2e": "Gegeg", "gst2f": "Gfefe",
        "tst2la": "Aagag", "tst2b": "Abgbg", "tst2c": "Acgcg", "tst2d": "Adgdg",
        "ltst2d": "Adcdc", "tst2e": "Aegeg", "tst2f": "Afefe", "tst2hg": "AGfGf",
        "hst2la": "agag", "hst2b": "bgbg", "hst2c": "cgcg", "hst2d": "dgdg",
        "lhst2d": "dcdc", "hst2e": "egeg", "hst2f": "fefe", "hst2hg": "GfGf", "hst2ha": "AGAG",

        // Triple Strikes (3 repeats)
        "st3la": "gagag", "st3b": "gbgbg", "st3c": "gcgcg", "st3d": "gdgdg", "lst3d": "cdcdc",
        "st3e": "aeaea", "st3f": "efefe", "st3hg": "fGfGf", "st3ha": "GAGAG",
        "gst3la": "Gagagag", "gst3b": "Gbgbgbg", "gst3c": "Gcgcgcg", "gst3d": "Gdgdgdg",
        "lgst3d": "Gdcdcdc", "gst3e": "Geaeaea", "gst3f": "Gfefefe",
        "tst3la": "Aagagag", "tst3b": "Abgbgbg", "tst3c": "Acgcgcg", "tst3d": "Adgdgdg",
        "ltst3d": "Adcdcdc", "tst3e": "Aeaeaea", "tst3f": "Afefefe", "tst3hg": "AGfGfGf",
        "hst3la": "agagag", "hst3b": "bgbgbg", "hst3c": "cgcgcg", "hst3d": "dgdgdg",
        "lhst3d": "dcdcdc", "hst3e": "eaeaea", "hst3f": "fefefe", "hst3hg": "GfGfGf", "hst3ha": "AGAGAG",

        // Double Grace Notes (generic 2-note clusters)
        "dlg": "dg", "dla": "da", "db": "db", "dc": "dc",
        "elg": "eg", "ela": "ea", "eb": "eb", "ec": "ec", "ed": "ed",
        "flg": "fg", "fla": "fa", "fb": "fb", "fc": "fc", "fd": "fd", "fe": "fe",
        "glg": "Gg", "gla": "Ga", "gb": "Gb", "gc": "Gc", "gd": "Gd", "ge": "Ge", "gf": "Gf",
        "tlg": "Ag", "tla": "Aa", "tb": "Ab", "tc": "Ac", "td": "Ad", "te": "Ae", "tf": "Af", "thg": "AG",

        // Cadences (phrase-ending figures — target note is High G) + fermata variants
        "cadged": "Ged", "cadge": "Ge", "caded": "ed", "cade": "e",
        "cadaed": "Aed", "cadae": "Ae", "cadgf": "Gf", "cadaf": "Af",
        "fcadged": "Ged", "fcadge": "Ge", "fcaded": "ed", "fcade": "e",
        "fcadaed": "Aed", "fcadae": "Ae", "fcadgf": "Gf", "fcadaf": "Af",

        // E, F & High G Throws (piobaireachd) + abbreviated variants
        "embari": "egfg", "endari": "eafa", "edre": "eafa",
        "chedari": "feGefe", "hedari": "eGefe",
        "pembari": "egfg", "pendari": "eafa", "pedre": "eafa",
        "pchedari": "feGefe", "phedari": "eGefe",
        // "chedare" (e-ending) shows up in real BWW files alongside
        // "chedari" (i-ending) — not in the source guide, but close enough in
        // spelling to the same ornament that it's almost certainly an
        // alternate transliteration rather than a distinct figure, so it's
        // aliased to the same sequence rather than left unrecognized.
        "chedare": "feGefe",

        // High A and D Throws (piobaireachd) + abbreviated variants
        "dili": "AG", "tra": "gdc", "htra": "dc", "tra8": "gdc", "pgrp": "gdg",
        "pdili": "AG", "ptra": "gdc", "phtra": "dc", "ptra8": "gdc",

        // Grace Note / Thumb / Half Throws (piobaireachd)
        "gedre": "Geafa", "dare": "feGe", "eedre": "ebfb", "gdare": "GfeGe",
        "tedre": "Aeafa", "tdare": "AfeGe", "tchechere": "AGeAe", "dre": "afa",
        "hedale": "eGe", "hchechere": "eAe",

        // Grips / Half Grips (piobaireachd: Deda, Enbain, Otro, Odro) + abbreviated variants
        "deda": "gdg", "enbain": "agdg", "otro": "bgdg", "odro": "cgdg", "adeda": "dgeg",
        "genbain": "Gagdg", "gotro": "Gbgdg", "godro": "Gcgdg", "gadeda": "Gdgeg",
        "tenbain": "Aagdg", "totro": "Abgdg", "todro": "Acgdg", "tadeda": "Adgeg",
        "penbain": "agdg", "potro": "bgdg", "podro": "cgdg", "padeda": "dgeg",

        // Echo Beat Grace Notes
        "echolg": "g", "echola": "a", "echob": "b", "echoc": "c", "echod": "d",
        "echoe": "e", "echof": "f", "echohg": "G", "echoha": "A",

        // Darodos (piobaireachd) + abbreviated variants
        "darodo": "gdgcg", "darodo16": "gdgcg", "hdarodo": "dgcg",
        "pdarodo": "gdgcg", "pdarodo16": "gdgcg", "phdarodo": "dgcg",

        // Miscellaneous (piobaireachd)
        "hiharin": "dagag", "rodin": "gbg", "din": "g", "phiharin": "dagag", "chelalho": "fde",

        // Leumluaths (piobaireachd)
        "lem": "gdg", "lemb": "gbg", "hlemla": "da", "hlemlg": "dg",
        "pl": "Xgdge", "plb": "Xgbge", "phlla": "Xdae",

        // Triplings (piobaireachd)
        "ptriplg": "Ggdge", "ptripla": "Gadae", "ptripb": "Gbdbe", "ptripc": "Gcdce",
        "pttriplg": "gdge", "pttripla": "adae", "pttripb": "bdbe", "pttripc": "cdce",
        "phtriplg": "Agdge", "phtripla": "Aadae", "phtripb": "Abdbe", "phtripc": "Acdce",

        // Crunluaths (piobaireachd)
        "crunl": "gdgeafa", "crunlb": "gbgeafa", "hcrunlla": "daeafa", "hcrunllgla": "dgeafa",
        "pc": "Xgdgeafa", "pcb": "Xgbgeafa", "phcla": "Xdaeafa",

        // Closed Crunluaths (piobaireachd)
        "crunlbrea": "gbgeafa", "crunlbbrea": "gdgegfg", "hcrunllabrea": "daeafa",
        "pcbrea": "gbgeafa", "pcbbrea": "gdgegfg", "phclabrea": "daeafa",

        // Crunluath / Edre a Machs (piobaireachd) + abbreviated dotted variants
        "pcmb": "Gbgdgbebfb", "pcmc": "Gcgdgcecfc", "pcmd": "Gbgdcdedfd",
        "edrelg": "egfg", "edrela": "eafa", "edreb": "ebfb", "edrec": "ecfc", "edred": "edfd",
        "pedreb": "ebfb", "pedrec": "ecfc", "pedred": "edfd"
    ]

    /// Whether `token` (case-insensitive) is a recognized embellishment.
    static func contains(_ token: String) -> Bool {
        graceLetters[token.lowercased()] != nil
    }

    /// Decodes `token`'s grace-letter string into playable pitches, skipping
    /// any `X` rendering-only placeholders. Returns nil for an unrecognized token.
    static func gracePitches(for token: String) -> [Pitch]? {
        guard let letters = graceLetters[token.lowercased()] else { return nil }
        return letters.compactMap { letter -> Pitch? in
            switch letter {
            case "g": return .lowG
            case "a": return .lowA
            case "b": return .b
            case "c": return .c
            case "d": return .d
            case "e": return .e
            case "f": return .f
            case "G": return .highG
            case "A": return .highA
            default: return nil // "X" placeholder or anything unexpected
            }
        }
    }
}
