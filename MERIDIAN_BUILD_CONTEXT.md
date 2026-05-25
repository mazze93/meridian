# Meridian — Build Context & Decision Record

> Companion to `CLAUDE.md`. Read when you need full rationale for a closed decision,
> the complete affect model specification, usability test protocols, or the cultural
> competence QA checklist. Not required reading for every session — reference as needed.

---

## Part 1 — Affect Model: Full Specification

### Theoretical Ground

Lisa Feldman Barrett's active inference account of constructed emotion (PMC5390700)
establishes the following constraints on system design:

**Interoceptive prediction** — The brain generates top-down predictions about internal
body state. Conscious affect is the brain's best guess, updated by incoming signals.

**Prediction error** — When afferent signals deviate from predictions, a prediction error
is generated. Large or repeated errors trigger allostatic recalibration: the brain updates
its model.

**Allostatic load** — Failure to successfully predict and prepare is experienced as
effortfulness or depletion — not as a named emotion.

**Interoceptive precision weighting** — The brain weights signals by estimated
reliability. The `clarity` dimension maps to this: low clarity = low precision on current
interoceptive signals. Foggy, unresolved body-state predictions.

**Emotion categories are constructed, never detected** — Emotion words are
constructions the brain uses to categorize continuous affect. Meridian has no access
to the user's emotion categories. It has access to three continuous dimensions only.
It must never name an emotion.

**Critical implication**: Meridian's prediction error signal is not a proxy for "the user
is stressed." It is a proxy for "this time window is producing more physiological
uncertainty than the user's own history predicts it should." The system's response is
a schedule observation, not a wellness intervention.

---

### Time-Window Buckets

| Bucket ID | Hours (local) | Days |
|-----------|---------------|------|
| wday-morning | 05:00–11:59 | Mon–Fri |
| wday-midday | 12:00–16:59 | Mon–Fri |
| wday-evening | 17:00–23:59 | Mon–Fri |
| wend-morning | 05:00–11:59 | Sat–Sun |
| wend-midday | 12:00–16:59 | Sat–Sun |
| wend-evening | 17:00–23:59 | Sat–Sun |

Midnight–05:00 → assigned to previous day's `wXXX-evening` bucket.
Six buckets total. Each has an independent baseline.

---

### Baseline Construction

**Minimum sample requirement**: 7 check-ins before any baseline is computed.
Below this threshold: bucket is `FORMING`. No prediction error computed.

**Rolling window**: Most recent 28 check-ins in the bucket (older retained for export).

**Computed per bucket** (per dimension V, A, C):
```
µ_V = mean(valence, last 28)
µ_A = mean(arousal, last 28)
µ_C = mean(clarity, last 28)
σ_V = std(valence, last 28)
σ_A = std(arousal, last 28)
σ_C = std(clarity, last 28)
```

**Stability threshold** — bucket marked `STABLE` when:
```
σ_V < 0.30 AND σ_A < 0.30 AND σ_C < 0.25
```
If any dimension exceeds its threshold: bucket is `FORMING_EXTENDED`.
No prediction error computed. Re-evaluated after each new check-in.

**Baseline states are internal only.** No UI indication of `FORMING`, `FORMING_EXTENDED`,
or `STABLE`. The enrichment unlock system handles surface-level data sufficiency disclosure.

---

### Prediction Error Computation

When a new check-in arrives in a `STABLE` bucket:
```
ε = √( (V_new − µ_V)² + (A_new − µ_A)² + (C_new − µ_C)² )
```

Maximum possible ε = √(4 + 4 + 1) = **3.0**

**Significance threshold**: ε_threshold = **0.85**

Rationale: ~28% of maximum distance. Given σ ≈ 0.25–0.30 per dimension, a check-in
must deviate approximately 2–3 standard deviations in combined space to cross this
threshold. Consistent with Barrett's allostatic recalibration criterion.

`ε ≥ 0.85` = high-error check-in for that bucket. Stored in AffectDoc with ε value,
bucket ID, and ISO timestamp.

---

### System Response Trigger

Schedule review prompt fires when:
```
count(high-error check-ins in same bucket, within rolling 7-day window) ≥ 3
```

**N = 3**. Rolling 7-day window from timestamp of most recent check-in in bucket,
looking backward. Not calendar week.

**14-day cooldown** after prompt shown or dismissed. No further prompts for that
bucket during cooldown.

**Prompt suppression conditions** (checked before display):
- Bucket is `FORMING` or `FORMING_EXTENDED` → suppress
- Enrichment layer suppressed for the day (3 dismissals) → suppress
- Bucket cooldown active (14 days since last prompt) → suppress
- Tailscale sync in progress → defer 60 seconds, re-evaluate

---

### Data Lifecycle

| Data type | Retention | Deletion |
|-----------|-----------|---------|
| Raw check-in (V, A, C, timestamp, bucket, event ref) | Indefinite local | User-initiated export + delete |
| High-error flag + ε value | With parent check-in | Deleted with parent |
| Rolling baseline (µ, σ) | Recomputed on demand; not persisted | No separate deletion |
| Prompt display log | 90 days | Rolling deletion at 90 days |

**Manual baseline reset**: Settings > Affect > "Reset my baseline for [bucket]"
Clears high-error count and cooldown. Does not delete raw check-ins.
Restores bucket to `FORMING` (requires 7 new check-ins to re-stabilize).

**Auto-decay**: No check-ins in 45 consecutive days → bucket moves to `DORMANT`.
Re-enters `FORMING` on next check-in. No user action required.

---

### What the Affect System Must Never Do

1. **Never name an emotion category.** Emotion words are user-constructed. The system has no access to them.
2. **Never display a valence or arousal value as a self-description.** Showing "your average valence is −0.4" can produce iatrogenic mood effects.
3. **Never suggest a cause for the prediction error.** The system sees affect dimensions and schedule data only. Causal claims are confabulation.
4. **Never trigger a response from a single high-error check-in**, regardless of ε magnitude.
5. **Never surface prediction error magnitude to the user.** ε is internal. Showing it creates gamification dynamics that distort future check-in behavior.

---

## Part 2 — Sync Architecture: Full Specification

### Why Automerge-Swift

Four candidates were evaluated:

| Candidate | Decision | Reason |
|-----------|----------|--------|
| Automerge-Swift | **Selected** | Pure Swift, correct offline merge, ARM-native, no FFI |
| Y.js/Yrs via C FFI | Eliminated | Rust FFI overhead disproportionate for solo Apple build |
| SQLite + LWW | Eliminated | Broken under clock skew in peer mesh without NTP server |
| Custom OT | Eliminated | Requires linearization point (server) |

### Memory and Storage Estimates

Post-compaction per device:
- Year 1 (2,000 events, 365 check-ins): ~1.5–2.5 MB
- Year 3 (6,000 events, 1,095 check-ins): ~4.5–7.5 MB

Uncompacted overhead: 3–5× raw JSON. Compaction reduces to ~1.5–2×.

### Automerge Merge Semantics for Meridian Fields

| Field | Automerge behavior | Meridian interpretation |
|-------|--------------------|------------------------|
| `title`, `location`, `notes` | Register: deterministic winner | Acceptable; conflicts rare in personal mesh |
| `startDate`, `endDate` | Register: deterministic winner | Later actor wins; both values in history |
| `contextProfileMappings` | Set: additive merge | Both offline additions survive; correct |
| `localFlags` | Set: additive merge | Flags accumulate; correct |
| `isDecompressed` | Register: LWW | Acceptable; informational flag |
| `checkIns` (AffectDoc) | Map: concurrent additions merge | Unique UUIDs; no conflicts possible |

### Sync Endpoints

```
GET  /meridian/sync/status
     → { peerID, lastSyncAt, eventDocCursor, affectDocCursor }

POST /meridian/sync/event-doc
     body: Automerge binary delta since cursor

POST /meridian/sync/affect-doc
     body: Automerge binary delta since cursor
```

Auth: `MeridianAuth` header — shared secret from Keychain.

### Schema Evolution Contract

**Additive changes** (new optional field):
1. Increment `schemaVersion`
2. New field is optional with nil default
3. v1.0 devices: Automerge preserves unknown fields as opaque CRDT state
4. No migration required on update

**Non-additive changes** (rename, type change, removal):
1. Increment `schemaVersion` to N
2. On app launch: if local `schemaVersion < N`, run `migrate(doc:from:to:)`
3. Migration reads old field, writes new field, marks old for deprecation
4. Cross-version sync: v1.0 device shows migration warning; does not corrupt data

**Migration warning copy** (exact):
> "This device is running an older version of Meridian. Some events may not display
> all fields until you update."

### Compaction Strategy

Compaction calls `compact()` on EventDoc and AffectDoc.
Prunes history unreachable from current state.
Retains last 30 days of operation history for debugging.
Does not delete any user-visible data.

Triggers:
- App background, if last compaction > 7 days ago
- After successful Tailscale sync, if document grew > 20% since last compaction
- Explicit: Settings > Storage > "Compact Meridian data"

**Revisit trigger**: Compacted EventDoc > 25 MB on any device.
First evaluate annual segmentation. If insufficient, evaluate Yrs migration.

---

## Part 3 — Cultural Competence QA Protocol

### Definition

Cultural competence = the system does not require users to distort, hide, simplify,
or perform their lives differently in order to use the calendar effectively.

Not about feature representation or demographic inclusion checkboxes. About whether
the underlying architecture models real life — including lives that do not map onto
conventional work/personal/school role categories.

---

### Five Testable UX Properties

#### Property 1 — Role Non-Exclusivity
A user can assign one event to multiple context profiles simultaneously.
Neither language nor UI implies one assignment is "correct" and others supplemental.

Pass criteria:
- Multi-profile assignment possible in event editor
- Zero instances of "primary profile," "main calendar" in assignment UI
- VoiceOver reads all assigned profiles with equal syntactic weight

Fail signal:
- Multi-profile assignment blocked or limited to one
- Any UI element implies one profile is more "real" than another
- "Other" as catch-all for events not matching five presets

#### Property 2 — Profile Label Non-Othering
Five defaults (Developer, Ops, Student, Learner, Minimal) do not position any as
"normal" with others as specialty accommodations.

Pass criteria:
- Each label interpretable as primary identity for at least one plausible target user
- No label named after a corporate archetype that others non-corporate workers
- Five profiles together do not form an implicit hierarchy from "serious" to "casual"

Fail signal:
- Mutual aid coordinator forced between "Ops" (corporate) and "Minimal" (implies low-structure)
- Any label carries implicit prestige gradient when read in sequence

#### Property 3 — Enrichment Content Non-Normalization
Affect-pairing logic does not select content implicitly positioning one cultural or
productivity paradigm as the correct response to a given affect state.

Pass criteria:
- ≥30% of content pool for each simulated state is culturally neutral
- No item in low-valence pool is "push through it" motivational
- Non-Western/non-secular content appears without opt-in gate

Fail signal:
- Low-valence pool pathologizes the state ("this too shall pass," "keep going")
- Non-Western content requires separate opt-in not required for Western content

#### Property 4 — Temporal Home Screen Universal Readability
Three time states (7 a.m., 2 p.m., 10 p.m.) work for non-conventional schedules,
non-single-household contexts, and non-neurotypical morning relationships.

Pass criteria:
- Copy does not use "workday," "your day," or "tonight" assuming conventional schedule
- "Morning anchors" concept is time-labeled, not role-labeled
- Events outside assumed category are not visually de-emphasized by default

Fail signal:
- 7 a.m. state shows only Developer/Ops profile events, hides health or caregiving
- 10 p.m. state presents "you're done" summary when obligations start at midnight

#### Property 5 — Affect Check-In Non-Prescriptiveness
Check-in UI does not, through visual design or spatial metaphors, imply certain affect
positions are more desirable, correct, or healthy than others.

Pass criteria:
- Color scheme does not map high-valence/high-arousal to "good" (no green = good, red = bad)
- VoiceOver axis labels are purely descriptive: "pleasant/unpleasant," "high energy/low energy," "clear/foggy"
- No "ideal zone" indicator, no smiley/frowny face, no visual aspiration cue

Fail signal:
- High-valence, high-arousal corner rendered warmer or more saturated
- VoiceOver reads "exhausted" for low arousal or "thriving" for high valence

---

### Code Audit Checklist — Identity-Adjacent Components

Applies to any component touching: context profiles, affect data, enrichment content
selection. Each item is answerable yes/no from source code without running the app.

1. **Binary pair prohibition** — Does any UI copy string use "personal" or "work" as a binary pair without allowing overlap or the absence of conventional employment?
   - Pass: words appear only in user-editable labels or are absent
   - Fail: hardcoded string pairs them as an implicit binary

2. **Enrichment fallback** — Does the enrichment content selection algorithm have a documented fallback for when affect data matches no tagged pool, and does that fallback avoid majority-culture normative defaults?
   - Pass: fallback pool explicitly defined in code comments, culturally neutral
   - Fail: fallback undefined or defaults to highest-rated general content regardless of framing

3. **Profile label editability** — Are context profile labels stored as user-editable strings, not hardcoded enums?
   - Pass: user-editable strings with defaults ✓ (CLOSED: D3-01)
   - Fail: hardcoded enums with no rename path

4. **No automatic primacy** — Does any event field or context profile field have a "primary" or "default" designation applied automatically rather than by user choice?
   - Pass: no field carries automatic primacy
   - Fail: any field auto-designated primary on first event creation

5. **Affect color symmetry** — Does the check-in 2D plane use a color scheme where the high-valence/high-arousal corner is more saturated, warmer, or visually prominent?
   - Pass: color treatment is symmetric or neutral with respect to affect direction
   - Fail: any visual treatment making "positive" states more appealing by design

6. **Profile name in system copy** — Are the five profile names referenced in system-generated copy (notifications, enrichment cards, schedule prompts) in a way that implies hierarchy?
   - Pass: profile names appear only in user-generated content
   - Fail: any system copy uses profile names to imply "serious" vs. "casual"

7. **Emotion word prohibition** — Does any system-generated copy in the affect feedback loop or schedule review prompt use an emotion word?
   - Pass: zero emotion words in all system-generated strings
   - Fail: any instance regardless of context

8. **Enrichment opt-in parity** — Does the affect-pairing algorithm require opt-in for non-Western/non-secular content while serving Western/secular content by default?
   - Pass: all content eligible for selection on affect-pairing alone, no cultural opt-in gate
   - Fail: any conditional routing non-majority-culture content behind a preference toggle

9. **No "Other" category** — Is there any code path producing an "Other," catch-all, or "Uncategorized" label for events not matching a profile?
   - Pass: unassigned events display with equal visual weight, no auto-applied fallback label
   - Fail: any auto-applied label implying the event doesn't belong

10. **Onboarding identity-free** — Does onboarding ask any question about profession, employment status, or life structure before the user has chosen to provide it?
    - Pass: onboarding requires only device connectivity and calendar permission
    - Fail: any prompt asking "what type of user are you?" before user initiates profile setup

---

### Usability Test Scenario Profiles (Summary)

Three full protocols exist for testing cultural competence with real participants.

**Scenario A — Devontae, 34**
Community health worker + MSW student + mutual aid network member.
Chronic fatigue (managed). Four overlapping life domains. Not a developer.
Tests: multi-domain event placement, unified week view, buffer concept, affect check-in neutrality.
Pass threshold: all four event types placed without forcing any into "other." Affect check-in generates no normative pressure.

**Scenario B — Marisol, 51**
Volunteer treasurer + PTA co-chair + part-time bookkeeper for two clients.
No primary employer. Mild presbyopia, larger Dynamic Type. WhatsApp-driven scheduling.
Tests: role-distinct overlapping events, filtered views, Dynamic Type compliance, monthly view presence.
Pass threshold: no profile label appropriate failure; no Dynamic Type truncation; monthly view present.

**Scenario C — Sage, 27, they/them**
Coffee shop worker + mutual aid housing justice coordinator (unpaid, 25–30 hrs/week).
ADHD (unmedicated by choice). Abandoned Fantastical, Notion Calendar, Apple Calendar.
Deeply skeptical of productivity apps and surveillance-adjacent tools.
Tests: two-domain event distinction, temporal home screen fit, affect check-in surveillance perception, soft-hold for provisional scheduling, profile label fit for organizing work.
Pass threshold: organizing work not forced into "Minimal." Check-in described as neutral-to-helpful, not tracking. At least one profile workable for organizing context without corporate label identification.

Full protocols including exact task scripts and debrief questions are in the pre-engineering decision documents (v1.0).

---

## Part 4 — Layer 1 Build Checklist

Use this checklist to verify Layer 1 is complete before any Layer 2 code is written.

### Package and Schema
- [ ] `Package.swift` declares Automerge-Swift dependency with pinned version
- [ ] `EventDoc` struct compiles with all fields from Document 2 §2.4
- [ ] `AffectDoc` struct compiles with all fields from Document 2 §2.4
- [ ] Both documents initialize to empty state correctly
- [ ] Both documents serialize to and deserialize from disk without data loss

### Encrypted Local Persistence
- [ ] AffectDoc written to encrypted local store (not UserDefaults, not plaintext)
- [ ] EventDoc written to encrypted local store
- [ ] Keychain used for encryption key; key survives app restart
- [ ] Decryption succeeds after app kill and relaunch

### Compaction
- [ ] `compact()` called on app background if last compaction > 7 days
- [ ] `compact()` called after sync if document grew > 20%
- [ ] Post-compaction document is valid and fully readable
- [ ] Compaction does not delete any user-visible data

### Sync Transport
- [ ] Local HTTP server binds to Tailscale IP on port 47301
- [ ] Server does not bind to non-Tailscale interfaces
- [ ] `MeridianAuth` header validated on all incoming requests
- [ ] Shared secret stored in Keychain; not hardcoded; not in UserDefaults
- [ ] `GET /meridian/sync/status` returns correct schema
- [ ] `POST /meridian/sync/event-doc` applies Automerge binary delta correctly
- [ ] `POST /meridian/sync/affect-doc` applies Automerge binary delta correctly
- [ ] Sync triggers fire correctly (foreground, tap, post-mutation debounced 30s)

### Merge Correctness
- [ ] Concurrent title edits on two devices produce deterministic winner; losing value in history
- [ ] Concurrent profile assignments on two devices both survive (Set merge)
- [ ] Concurrent AffectDoc check-ins on two devices both survive (Map merge by UUID)
- [ ] Schema v1.0 device receiving v1.1 document does not crash and does not strip unknown fields

### Schema Evolution
- [ ] `schemaVersion` field present and readable in both documents
- [ ] Additive field addition on v1.1 produces no migration on v1.0 device
- [ ] Non-additive change triggers `migrate(doc:from:to:)` on app launch
- [ ] Migration warning shown when cross-version sync detected

---

## Quick Reference — Decision IDs

Full rationale for every closed decision is in the pre-engineering decision documents (v1.0).
Use decision IDs (D1-xx, D2-xx, D3-xx) when referencing decisions in commit messages and code comments.

| Range | Document |
|-------|----------|
| D1-01 – D1-10 | Affect Model (Barrett, prediction error, prompts) |
| D2-01 – D2-10 | Sync Architecture (Automerge-Swift, schema, compaction) |
| D3-01 – D3-08 | Cultural Competence QA (properties, audit checklist) |
