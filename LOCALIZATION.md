# PulseTrackr Localization

PulseTrackr is set up for localization via a **String Catalog** so it can ship in
all App Store regions. This is a scaffold: the infrastructure is in place and one
example language (Spanish) is wired end-to-end. Translating the rest is incremental.

## How it works

- User-facing copy uses SwiftUI `Text("…")`, which resolves through a
  `LocalizedStringKey` automatically. String *variables* must be typed
  `LocalizedStringKey` (not `String`) to localize — see `LocationPromptCard` in
  `app/SharedComponents.swift` for the pattern.
- `app/Localizable.xcstrings` is the single source of truth for translations.
- `SWIFT_EMIT_LOC_STRINGS = YES` is set, so Xcode extracts new literal strings into
  the catalog automatically when you open it in the editor.
- The development language is English (`en`); `es` is included as a worked example.
  At build time each language compiles into its own `*.lproj/Localizable.strings`
  inside the app bundle (verified: `es.lproj` ships with the Spanish strings).

## Adding a language

1. In Xcode, open `Localizable.xcstrings` → click **+** in the language bar and pick
   the language. (This also adds it to the project's `knownRegions`. `en`, `Base`,
   and `es` are already registered.)
2. Fill in the translated values. Strings left untranslated fall back to English.
3. Build — Xcode generates the new `*.lproj` automatically.

## Adding / translating strings

1. Use a literal `Text("New copy")` in SwiftUI (or `String(localized:)` in non-View
   code). Avoid `Text(someStringVariable)` unless the variable is a
   `LocalizedStringKey`.
2. Build once; Xcode extracts the new key into `Localizable.xcstrings`.
3. Add translations per language in the catalog editor.

## Not yet migrated

Only the location-prompt strings are seeded as the demonstration. The remaining
user-facing strings across the app (feed, map, settings, SOS, detail views) still
need to be reviewed and added to the catalog before a fully-localized release.
This is intentionally incremental and non-blocking for an English-first launch.
