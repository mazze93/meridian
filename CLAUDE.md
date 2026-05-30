# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Meridian — Claude Code Project Instructions

> Read this file in full at the start of every session.
> All decisions marked CLOSED are not subject to re-examination unless the founder
> explicitly says "reopen [decision ID]." If a request would implicitly re-open a closed
> decision, say so before proceeding.

---

## What Meridian Is

A privacy-first, local-first calendar for Apple platforms (iPhone, iPad, macOS menu bar).
Sync runs exclusively over Tailscale — peer mesh, 1–3 personal devices. No cloud
accounts. No server. No backend. No iCloud sync.

Target users: developers, nonprofit operators, students, independent learners,
neurodivergent users. Accessibility is structural, not additive.

---

## Build Commands

> The Swift package lives at `tools/meridian/` in the monorepo — run all commands from there.
> `Package.swift` currently declares only the `MeridianCore` library + its test target.
> `MeridianUI` / `MeridianApp` targets return at Layer 2, when they gain real sources
> (SPM cannot build an empty-source target, and stubs are prohibited).

```bash
# Resolve dependencies (run after Package.swift is created or updated)
swift package resolve

# Build all targets
swift build

# Run all tests
swift test

# Run a specific test target
swift test --filter MeridianCoreTests

# Run a single test method
swift test --filter MeridianCoreTests/DocumentModelTests/testEventDocCodableRoundTrip

# Build for release (use before measuring compacted document sizes)
swift build -c release
```

SwiftLint: add to Package.swift as a plugin once Layer 1 compiles. Run with `swift package plugin lint`.

### Build Notes

- **Linker warning** (expected, ignore): `building for macOS-13.0, but linking with dylib ... built for newer version 26.0` — comes from Automerge-Swift's prebuilt binary; not actionable.
- **Dual test output** (expected): `swift test` runs two suites — XCTest (20 tests pass as of 2026-05-30) and Swift Testing (shows `0 tests in 0 suites`). The second block is normal; no `@Test` macros exist yet.

---

## Repository Structure (Target)

```
Meridian/
├── CLAUDE.md                    ← this file
├── MERIDIAN_BUILD_CONTEXT.md    ← full decision record (read for deep context)
├── meridian-decisions.xml       ← machine-readable closed decision table
├── Package.swift
├── Sources/
│   ├── MeridianCore/            ← data models, CRDT logic, sync protocol
│   │   ├── Documents/           ← EventDoc.swift, AffectDoc.swift
│   │   ├── Sync/                ← TailscaleTransport.swift, SyncCoordinator.swift
│   │   ├── Affect/              ← BaselineEngine.swift, PredictionError.swift
│   │   └── Keychain/            ← KeychainService.swift
│   ├── MeridianUI/              ← SwiftUI views only; no business logic
│   │   ├── Calendar/            ← day view, week view, month view
│   │   ├── Affect/              ← check-in control, no scores displayed
│   │   └── Settings/            ← sync settings, storage, baseline reset
│   └── MeridianApp/             ← app entry point, scene delegates
└── Tests/
    ├── MeridianCoreTests/
    └── MeridianUITests/
```

---

## Build Layer Sequence — ENFORCED

Layer 1 is a hard blocker. Do not generate Layer 2 or Layer 3 code until
Layer 1 is complete and passing its test checklist.

### Layer 1 — Tailscale + CRDT Substrate
1. Package.swift with Automerge-Swift dependency
2. EventDoc and AffectDoc struct definitions
3. Document initialization, serialization, encrypted local persistence
4. Compaction logic (background + post-sync triggers)
5. Local HTTP server on port 47301 bound to Tailscale interface
6. Peer discovery and binary delta sync protocol
7. MeridianAuth shared secret via Keychain

### Layer 2 — Calendar Core UI
Temporal home screen (iPhone), iPad layout, macOS menu bar popover.
SwiftUI throughout. EventKit bridge.

### Layer 3 — Affect + Enrichment
Affect check-in control, baseline engine, prediction error computation,
schedule review prompt, enrichment unlock system.

The full Layer 1 pass/fail checklist is in `MERIDIAN_BUILD_CONTEXT.md` Part 4.

---

## Build Progress

> Update this section as steps land. Dates are absolute (YYYY-MM-DD).

### Layer 1 — Tailscale + CRDT Substrate (in progress)

| Step | Status | Notes |
|------|--------|-------|
| 1. Package.swift + Automerge-Swift | ✅ done (2026-05-25) | Automerge-Swift pinned `from: "0.7.2"`. Manifest trimmed to `MeridianCore` only. |
| 2. EventDoc + AffectDoc structs | ✅ done (2026-05-25) | All records Codable/Equatable/Sendable. 7/7 model tests pass (`DocumentModelTests`). |
| 3. Init, serialization, encrypted local persistence | ✅ done (2026-05-30) | `KeychainService` (CryptoKit, ChaChaPoly key in Keychain w/ `AfterFirstUnlockThisDeviceOnly`), `EncryptedStore` (magic ‖ version ‖ nonce ‖ AEAD; header AAD-bound; atomic write), `DocumentStore<Model>` (Codable ↔ Automerge bridge via `AutomergeEncoder`/`AutomergeDecoder`). 20/20 tests pass — incl. kill+relaunch round-trip for both docs and current-reader-loads-future-blob (D2-10 load side). Closes D2-11, D2-12. |
| 4. Compaction logic | ⬜ NEXT | `compact()` on background (>7d) and post-sync (>20% growth). See Compaction Triggers. Automerge has no explicit `compact()` — `Document.save()` already produces the compacted form, so compaction = `Document(doc.save())`. Trigger policy lives in this step. |
| 5. Local HTTP server on :47301 | ⬜ pending | Bind Tailscale interface only; never non-Tailscale. `MeridianAuth` header validated. |
| 6. Peer discovery + binary delta sync | ⬜ pending | Endpoints in Sync Protocol section. |
| 7. MeridianAuth shared secret via Keychain | ⬜ pending | Shared secret from Keychain; never hardcoded, never UserDefaults. |

**Schema fields resolved 2026-05-25:**
- `SoftHoldRecord`: `id`, `title`, `startDate`, `endDate`, `contextProfiles: Set<String>`, `createdAt`.
  Soft holds carry context-profile assignments (founder decision) — non-exclusive, no primary
  (D3 Property 1, audit #4); empty set = unassigned, renders with equal weight, no fallback label (audit #9).
- `BufferRecord`: `id`, `eventRef`, `leadingSeconds`, `trailingSeconds`, `createdAt`.
  Separate leading/trailing per spec wording "before and/or after."

**Persistence architecture resolved 2026-05-30 (closes D2-11, D2-12):**
- `KeychainService` — 256-bit symmetric key generated on first launch via `SecRandomCopyBytes`,
  stored as `kSecClassGenericPassword` under service `com.meridian.localstore.v1`, accessible
  `AfterFirstUnlockThisDeviceOnly` (no iCloud Keychain escrow).
- `EncryptedStore` — file format `MRDN(4) ‖ ver(1) ‖ nonce(12) ‖ AEAD(ciphertext+tag)` using
  CryptoKit `ChaChaPoly`. Header is bound as AAD, so tampering with the version byte or nonce
  fails decryption. Atomic write via temp file + `FileManager.replaceItem`. `fileNotFound` is
  distinct from `decryptionFailed` so callers can tell first-launch from corruption.
- `DocumentStore<Model: Codable>` — bridges `EventDoc`/`AffectDoc` to Automerge via
  `AutomergeEncoder` / `AutomergeDecoder`, persists `Document.save()` as opaque bytes (D2-12).
- **Architectural caveat for Layer 1 step 5+ (sync):** `DocumentStore` constructs a fresh
  `Automerge.Document` per save. Unknown future-schema fields survive the *load* side of a
  cross-version blob (test: `testCurrentReaderLoadsFutureBlobWithUnknownFields`) but would be
  dropped on write-back. The sync coordinator must own a long-lived `Automerge.Document` and
  merge deltas into it directly — never round-trip through `DocumentStore.save()` during sync.

**Next action:** Layer 1 step 4 — compaction policy. `Document(Document.save())` round-trip is
the compaction primitive; build the trigger policy (background >7d, post-sync >20% growth,
explicit Settings action) around it. Do not start Layer 2/3 while Layer 1 is open.

---

## Closed Decisions — Do Not Re-Litigate

Full rationale for every decision is in `meridian-decisions.xml` and
`MERIDIAN_BUILD_CONTEXT.md`. Use decision IDs in commit messages and code comments.

| ID | Decision |
|----|----------|
| D1-01 | Minimum 7 check-ins before baseline computed per bucket |
| D1-02 | Rolling 28-check-in window for baseline |
| D1-03 | Stability threshold: σ < 0.30 (V, A), σ < 0.25 (C) |
| D1-04 | Prediction error: Euclidean distance in 3D affect space |
| D1-05 | ε_threshold = 0.85 (≈28% of max distance of 3.0) |
| D1-06 | N = 3 high-error check-ins in 7-day rolling window triggers prompt |
| D1-07 | 14-day cooldown after prompt shown per bucket |
| D1-08 | Schedule review prompt is the only system response — no wellness intervention |
| D1-09 | Emotion words prohibited in ALL system-generated copy — zero exceptions |
| D1-10 | Manual baseline reset per-bucket in Settings; auto-decay at 45 days |
| D2-01 | Conflict resolution: Automerge-Swift — not Y.js, not SQLite LWW, not OT |
| D2-02 | Y.js/Yrs eliminated — Rust FFI overhead disproportionate for solo build |
| D2-03 | SQLite + LWW eliminated — broken under clock skew in peer mesh |
| D2-04 | Custom OT eliminated — requires server/linearization point |
| D2-05 | Two documents: EventDoc + AffectDoc |
| D2-06 | Sync port: 47301 (user-configurable) |
| D2-07 | Compaction: automatic on background + post-sync if >20% growth |
| D2-08 | Schema evolution: additive = no migration; non-additive = versioned migrate() |
| D2-09 | Revisit trigger: compacted EventDoc > 25 MB → evaluate annual segmentation |
| D2-10 | Cross-version sync: preserve unknown fields; show migration warning to user |
| D2-11 | Local at-rest crypto: CryptoKit ChaChaPoly (Apple-platforms-only posture extension of D2-01/D2-02) |
| D2-12 | Encryption granularity: wrap full Automerge `save()` as opaque bytes; never field-encrypt |
| D3-01 | Context profiles: user-editable strings; five named defaults; stable UUID internal key |
| D3-02 | Cultural competence = system does not require users to distort their lives |
| D3-03 | Enrichment unlocks through use + affect thresholds only — never payment |

---

## Architecture Overview

**MeridianCore** owns all business logic. **MeridianUI** is views only — no business logic crosses into UI. **MeridianApp** is the entry point only.

Data flows one way: MeridianCore mutates CRDT documents → Automerge-Swift serializes → encrypted local store. Sync reads binary deltas from the store and exchanges them with peers over HTTP on the Tailscale interface. UI reads from the document; it never writes directly.

Key architectural constraint: the local HTTP server binds exclusively to the Tailscale IP. If Tailscale is not running, sync is unavailable — not degraded, simply unavailable. There is no fallback transport.

The affect model is computation-only. `BaselineEngine` reads `AffectDoc`, computes µ/σ per bucket, computes ε per new check-in, and writes `isHighError` and `epsilon` back into the check-in. It never surfaces those values to the UI as readouts. The UI receives only the schedule review prompt trigger signal.

---

## Affect Model — Barrett Constructed Emotion (PMC5390700)

Three dimensions stored as Float32:

| Dimension | Range | Maps To |
|-----------|-------|---------|
| Valence | −1.0 to +1.0 | Core affect valence |
| Arousal | −1.0 to +1.0 | Core affect arousal |
| Clarity | 0.0 to 1.0 | Interoceptive precision weighting |

Six time-window buckets (weekday/weekend × morning/midday/evening).
Midnight–05:00 assigned to previous day's evening bucket.

Prediction error formula:
```
ε = √( (V_new − µ_V)² + (A_new − µ_A)² + (C_new − µ_C)² )
```
Maximum ε = 3.0. Threshold ε_threshold = 0.85.

Bucket states: `FORMING` (<7 check-ins), `FORMING_EXTENDED` (≥7 but σ exceeds threshold), `STABLE`, `DORMANT` (no check-ins in 45 days). These are internal only — no UI indication.

---

## Data Schema (Automerge-Swift)

```swift
// EventDoc — top-level CRDT document
struct EventDoc: Codable {
    var schemaVersion: Int
    var events: [String: EventRecord]           // keyed by Meridian UUID
    var contextProfileMappings: [String: [String]] // eventID → [profileIDs]
    var softHolds: [String: SoftHoldRecord]
    var buffers: [String: BufferRecord]
}

// AffectDoc — separate CRDT document
struct AffectDoc: Codable {
    var schemaVersion: Int
    var checkIns: [String: AffectCheckIn]       // keyed by UUID
    var bucketBaselines: [String: BucketBaseline]
    var promptLog: [String: PromptLogEntry]
}

// AffectCheckIn
struct AffectCheckIn: Codable {
    var id: String
    var valence: Float        // −1.0 to +1.0
    var arousal: Float        // −1.0 to +1.0
    var clarity: Float        // 0.0 to 1.0
    var bucketID: String
    var eventRef: String?     // optional link to EventRecord.meridianID
    var submittedAt: Date
    var epsilon: Float?       // nil if bucket is FORMING
    var isHighError: Bool
}

// SoftHoldRecord — provisional, uncommitted time block
struct SoftHoldRecord: Codable {
    var id: String
    var title: String
    var startDate: Date
    var endDate: Date
    var contextProfiles: Set<String>  // profile UUIDs; non-exclusive, no primary; empty = unassigned
    var createdAt: Date
}

// BufferRecord — protected breathing room around an event
struct BufferRecord: Codable {
    var id: String
    var eventRef: String      // EventRecord.meridianID
    var leadingSeconds: TimeInterval   // before the event
    var trailingSeconds: TimeInterval  // after the event
    var createdAt: Date
}
```

---

## Sync Protocol

- Transport: local HTTP server on Tailscale IP, port 47301
- Auth header: `MeridianAuth` — shared secret from Keychain, exchanged at onboarding
- Endpoints:
  - `GET /meridian/sync/status` → `{ peerID, lastSyncAt, eventDocCursor, affectDocCursor }`
  - `POST /meridian/sync/event-doc` → Automerge binary delta since cursor
  - `POST /meridian/sync/affect-doc` → Automerge binary delta since cursor
- Sync triggers: app foreground (if last sync > 5 min), explicit tap, post-mutation (30s debounce)
- Typical delta size: < 50 KB per sync pair for daily usage

---

## Code Generation Rules

- Every function is fully implemented. No TODOs, stubs, or placeholder comments.
- Functions ≤ 50 lines. Files ≤ 300 lines.
- Separate concerns strictly: UI / logic / data / sync live in separate files.
- No hardcoded secrets. Keychain for shared secrets and sensitive tokens.
- No `UserDefaults` for sensitive data. Keychain for secrets; encrypted local store for affect data.
- HTTPS only for any external calls (rare; enrichment content is bundled).
- Every code response includes:
  1. Assumptions
  2. What's being built
  3. Code block(s)
  4. Explanation
  5. Usage example
  6. Testing checklist (3–5 items)

---

## Accessibility — Structural, Not a Feature

WCAG 2.1 AA minimum. Non-negotiable. Not a post-MVP item.

Every UI component must answer all five:
1. **VoiceOver**: label, hint, trait
2. **Dynamic Type**: behavior at XXXL size
3. **Reduce Motion**: alternative animation or none
4. **High Contrast / Grayscale**: compatible rendering
5. **Cognitive load**: max simultaneous decisions on screen = 3

Additional requirements:
- Touch targets ≥ 44×44pt
- Color is NEVER the sole indicator of state
- No VoiceOver label that uses an emotion word or implies affect evaluation

---

## Privacy Rules

- Affect data: local only. Never transmitted. Never displayed back to user as a score or dimensional readout.
- No engagement metrics: no streaks, no completion percentages, no "you were productive."
- No telemetry without explicit opt-in.
- No enrichment content requiring a network call at display time.
- Enrichment content: bundled or permanently cached after one user-initiated download.

---

## Copy Prohibitions — Zero Exceptions

### Prohibited in ALL system-generated strings:
`stress`, `anxiety`, `burnout`, `overwhelm`, `exhaustion`, `tired`, `drained`,
`frustrated`, `excited`, and all derivatives of the above.

### Prohibited constructions in schedule review prompts:
- Causal attribution: "because of," "due to," "from" constructions
- Imperatives implying obligation: "you should," "try to," "make sure"
- Any sentence naming an emotion category
- Any call-to-action opening a mood-logging or journaling flow

### Prohibited in context profile UI:
- "primary profile," "main calendar," "default profile" (auto-applied)
- "Other" as a catch-all for unclassified events
- Hierarchical framing implying some profiles are for "serious" users

---

## Schedule Review Prompt Copy (Locked)

### wday-morning
> This morning window has been running differently than your usual mornings.
> Your last few check-ins here landed further from your typical range. Worth a look at
> what's loading up before noon?
> [Review morning blocks →]

### wday-midday
> This afternoon pattern looks heavier than your afternoons usually do.
> Something in this window is landing differently than your baseline. Want to look at
> how much is stacking here?
> [Review afternoon blocks →]

### wend-* (any weekend bucket)
> This part of your weekend has been running differently lately.
> Your check-ins here have been outside your usual range. Worth a look at what you're
> holding in this time?
> [Review this block →]

Placement: inline card in day view, bottom of event stack. Never modal. Never push notification. Never menu bar popover.

---

## What Not To Do

- Do not suggest iCloud sync, cloud sync, or any server-side component.
- Do not use emotion category words in any system-facing copy.
- Do not re-open closed decisions without being explicitly asked.
- Do not generate UI where color alone indicates state, status, or profile.
- Do not add enrichment features requiring a network call at display time.
- Do not position accessibility as a post-MVP consideration.
- Do not generate Layer 2 or 3 code while Layer 1 tests are failing.

---

## Response Format

Prepend every code response with:
```
Assumptions: [bullet list of key inferences]
```

End every response with:
```
⬡ Meridian · Layer [N] — [Layer name] · [Current surface]
```

Append `[CLOSED]` if the response closes a decision.
Append `[NEEDS DECISION]` if the response surfaces an open question requiring founder input.

When updating existing code, show BEFORE and AFTER with a one-line reason.

---

## Context Profile Defaults

Five named defaults. Labels are user-editable strings. Internal identifier is a stable UUID.
The label is a separate editable string — not an enum.

| Default Label | Internal UUID | Notes |
|---------------|--------------|-------|
| Developer | stable UUID | User-renameable |
| Ops | stable UUID | User-renameable |
| Student | stable UUID | User-renameable |
| Learner | stable UUID | User-renameable |
| Minimal | stable UUID | User-renameable |

Events may be assigned to multiple profiles simultaneously. No profile is "primary."

---

## Compaction Triggers

Run `compact()` on EventDoc and AffectDoc:
- On app background, if last compaction > 7 days ago
- After each successful Tailscale sync, if document size grew > 20% since last compaction
- On explicit user action: Settings > Storage > "Compact Meridian data"

Post-compaction size targets:
- Year 1: ~1.5–2.5 MB compacted
- Year 3: ~4.5–7.5 MB compacted

Revisit trigger: if compacted EventDoc > 25 MB, evaluate annual segmentation first,
then evaluate Yrs migration.

---

## Cultural Competence — Five Testable Properties

These are pass/fail, not aspirational. Code audit runs against these before each layer ships.

1. **Role non-exclusivity** — single event assignable to multiple profiles; no hierarchical copy
2. **Profile label non-othering** — no label implies "normal" vs. specialty accommodation
3. **Enrichment non-normalization** — no content implicitly positions one cultural paradigm as correct
4. **Temporal home screen universal readability** — three time states work for non-conventional schedules
5. **Affect check-in non-prescriptiveness** — no visual or copy treatment implying a "correct" affect position

---

## Reference

Full decision rationale and usability test protocols:
→ `MERIDIAN_BUILD_CONTEXT.md` in this repository root

Machine-readable closed decision table:
→ `meridian-decisions.xml` in this repository root

Barrett theoretical grounding: PMC5390700
Automerge-Swift package: https://github.com/automerge/automerge-swift
