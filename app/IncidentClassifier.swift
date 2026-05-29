import Foundation

struct IncidentClassification: Equatable {
    var category: IncidentCategory
    var subtype: IncidentSubtype
    var severity: IncidentSeverity
    var reason: String
}

enum IncidentClassifier {
    static func classify(title: String, summary: String) -> IncidentClassification {
        let text = "\(title) \(summary)".lowercased()

        if containsAny(text, ["kidnap", "abduct", "bandit", "hostage", "gbomo gbomo", "gbomogbomo"]) {
            return IncidentClassification(category: .security, subtype: .kidnapping, severity: .urgent, reason: "Matched kidnapping or abduction language.")
        }

        if containsAny(text, ["gunshot", "gun shot", "shooting", "shots fired", "gunfire", "armed men"]) {
            return IncidentClassification(category: .security, subtype: .gunshots, severity: .urgent, reason: "Matched gunfire or armed threat language.")
        }

        if containsAny(text, ["robbery", "armed robber", "thief", "stolen at gunpoint"]) {
            return IncidentClassification(category: .security, subtype: .armedRobbery, severity: .urgent, reason: "Matched robbery language.")
        }

        if containsAny(text, ["one chance", "one-chance", "fake taxi", "fake bus"]) {
            return IncidentClassification(category: .security, subtype: .oneChance, severity: .high, reason: "Matched one-chance transit threat language.")
        }

        if containsAny(text, ["carjack", "snatched car", "stolen car"]) {
            return IncidentClassification(category: .security, subtype: .carjacking, severity: .high, reason: "Matched carjacking language.")
        }

        if containsAny(text, ["clash", "fight", "riot", "communal", "cultist", "cult clash"]) {
            return IncidentClassification(category: .security, subtype: .communalClash, severity: .high, reason: "Matched violent clash language.")
        }

        if containsAny(text, ["checkpoint", "road checkpoint", "extortion"]) {
            return IncidentClassification(category: .security, subtype: .checkpointIssue, severity: .medium, reason: "Matched checkpoint issue language.")
        }

        // More specific road conditions before the generic crash check so that
        // "bad road causing accidents" doesn't get swallowed by the accident rule.
        if containsAny(text, ["flooded road", "road flooded", "road waterlogged"]) {
            return IncidentClassification(category: .traffic, subtype: .floodedRoad, severity: .medium, reason: "Matched flooded road language.")
        }

        if containsAny(text, ["bad road", "pothole", "road damage"]) {
            return IncidentClassification(category: .traffic, subtype: .badRoad, severity: .medium, reason: "Matched road hazard language.")
        }

        if containsAny(text, ["accident", "crash", "collision", "hit and run", "hit-and-run", "motor accident", "car tumble"]) {
            return IncidentClassification(category: .traffic, subtype: .crash, severity: .high, reason: "Matched road crash language.")
        }

        if containsAny(text, ["roadblock", "road block", "blocked road", "blocked route"]) {
            return IncidentClassification(category: .traffic, subtype: .roadblock, severity: .medium, reason: "Matched roadblock language.")
        }

        if containsAny(text, ["traffic", "gridlock", "go slow", "hold up", "holdup", "serious traffic", "die traffic", "tight hold up", "wahala for road"]) {
            return IncidentClassification(category: .traffic, subtype: .gridlock, severity: .medium, reason: "Matched traffic delay language.")
        }

        // Fire terms. Word-boundary matching (see `containsAny`) keeps "fire" inside
        // "ceasefire" from triggering. Malls/plazas fall through to building fire;
        // only market/shop/store map to the market-fire subtype.
        if containsAny(text, ["fire", "burning", "smoke", "flames", "fire outbreak", "catch fire", "on fire", "dey burn", "inferno", "blaze"]) {
            // Malls/plazas/complexes are buildings, not markets — check them first so
            // "shopping complex" isn't pulled into market fire by the "shop" prefix.
            if containsAny(text, ["mall", "plaza", "shopping complex", "shopping mall", "commercial building"]) {
                return IncidentClassification(category: .fire, subtype: .buildingFire, severity: .urgent, reason: "Matched a fire at a mall, plaza, or commercial building.")
            }

            if containsAny(text, ["market", "shop", "store"]) {
                return IncidentClassification(category: .fire, subtype: .marketFire, severity: .urgent, reason: "Matched market or shop fire language.")
            }

            return IncidentClassification(category: .fire, subtype: .buildingFire, severity: .urgent, reason: "Matched fire or smoke language.")
        }

        if containsAny(text, ["gas leak", "gas smell", "cylinder", "gas cylinder"]) {
            return IncidentClassification(category: .fire, subtype: .gasLeak, severity: .urgent, reason: "Matched gas leak language.")
        }

        if containsAny(text, ["explosion", "blast", "bomb blast", "pipeline explosion"]) {
            return IncidentClassification(category: .fire, subtype: .explosion, severity: .urgent, reason: "Matched explosion language.")
        }

        // Note: "accident victim" is intentionally omitted — the earlier crash rule
        // already claims any text containing "accident".
        if containsAny(text, ["injury", "injured", "ambulance", "bleeding", "bleed", "hospital emergency", "person dey bleed"]) {
            return IncidentClassification(category: .medical, subtype: .medicalEmergency, severity: .high, reason: "Matched medical emergency language.")
        }

        if containsAny(text, ["cholera", "lassa", "outbreak", "many sick", "infection", "disease outbreak", "many people sick"]) {
            return IncidentClassification(category: .medical, subtype: .suspectedOutbreak, severity: .high, reason: "Matched suspected outbreak language.")
        }

        if containsAny(text, ["flood", "flooding", "water logged", "waterlogged", "submerged"]) {
            return IncidentClassification(category: .weather, subtype: .flooding, severity: .high, reason: "Matched flooding language.")
        }

        if containsAny(text, ["heavy rain", "storm", "wind damage"]) {
            return IncidentClassification(category: .weather, subtype: .stormDamage, severity: .medium, reason: "Matched severe weather language.")
        }

        if containsAny(text, ["light out", "power outage", "blackout", "no light", "nepa", "electricity", "phcn", "disco take light", "no current"]) {
            return IncidentClassification(category: .utilities, subtype: .powerOutage, severity: .low, reason: "Matched power outage language.")
        }

        if containsAny(text, ["fuel queue", "fuel scarcity", "no fuel", "petrol queue", "filling station queue"]) {
            return IncidentClassification(category: .utilities, subtype: .fuelScarcity, severity: .medium, reason: "Matched fuel scarcity language.")
        }

        if containsAny(text, ["building collapse", "collapsed building", "house collapse", "structural failure", "building fell", "house fell", "don collapse", "caved in", "multi-storey collapse", "high-rise collapse", "school collapse"]) {
            return IncidentClassification(category: .structure, subtype: .buildingCollapse, severity: .urgent, reason: "Matched building collapse language.")
        }

        if containsAny(text, ["bridge collapse", "collapsed bridge"]) {
            return IncidentClassification(category: .structure, subtype: .bridgeCollapse, severity: .urgent, reason: "Matched bridge collapse language.")
        }

        if containsAny(text, ["unsafe building", "cracks in wall", "cracks in building", "weak structure", "dilapidated building", "building at risk"]) {
            return IncidentClassification(category: .structure, subtype: .unsafeBuilding, severity: .medium, reason: "Matched unsafe building language.")
        }

        if containsAny(text, ["missing person", "missing child", "missing woman", "missing man", "lost child"]) {
            return IncidentClassification(category: .community, subtype: .missingPerson, severity: .high, reason: "Matched missing person language.")
        }

        if containsAny(text, ["safe route", "avoid route", "pass here"]) {
            return IncidentClassification(category: .community, subtype: .safeRoute, severity: .low, reason: "Matched safe-route language.")
        }

        return IncidentClassification(category: .security, subtype: .suspiciousActivity, severity: .medium, reason: "No strong match yet. Defaulting to a general safety signal.")
    }

    /// Matches a term at a word boundary (prefix), so stemmed forms still match
    /// ("kidnap" → "kidnapping") while embedded matches do not ("fire" inside
    /// "ceasefire"). `text` is expected to be lowercased already.
    private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { term in
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: term)
            return text.range(of: pattern, options: [.regularExpression]) != nil
        }
    }
}
