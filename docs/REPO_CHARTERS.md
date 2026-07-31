# Repository Charters and Dependency Contract

**Single rule:** isochrones determines who and where, mufflyaccess certifies how
many, twostep measures access, and cliff projects the future.

This document is the authoritative charter for the four-repo workforce lineage. It
fixes **one direction of dependency** so that provider-level truth is built once,
published once, and consumed everywhere else without redefinition. Any change to a
charter is a governance change, not a code change: update this file first.

Status: authoritative. Authored from `twostep@main`, 2026-07-27. Intended to be copied
verbatim into `isochrones/docs/`, `mufflyaccess/`, and `cliff/docs/` so every repo
carries the same contract.

---

## Dependency direction (the ONLY allowed direction)

```
        ABOG / ABU source files
                  |
                  v
              isochrones          provider-level construction
                  |
                  v
        canonical hashed artifacts (parquet + csv + manifest)
                  |
                  v
             mufflyaccess         validated, stable R API
                  |
                  v
     cliff / twostep / manuscripts / apps
```

**There are no reverse arrows.** A repo may only read artifacts produced by a repo
above it. A repo may never reach back up to rebuild, re-derive, or override an
upstream quantity. If a consumer needs a different number, the change is made
upstream and re-published, never patched downstream.

| Arrow | Means |
|---|---|
| source to isochrones | isochrones ingests raw rosters; nobody else touches raw rosters for the baseline |
| isochrones to artifacts | isochrones emits versioned, hashed, immutable files |
| artifacts to mufflyaccess | mufflyaccess reads those files, validates them, and is the sole publisher of the number |
| mufflyaccess to consumers | every consumer gets the number through the mufflyaccess API, with provenance |

---

## Charter: isochrones - build the canonical provider roster

**Owns provider-level truth.** isochrones is the single place where the raw rosters
become people, and where people become a workforce table.

Responsibilities:
- Raw ABOG and ABU roster ingestion
- NPI matching and deduplication
- Certification year and retirement year
- Active-in-year logic
- Geography and geocoding
- Producing a versioned, immutable provider snapshot
- Producing the 2013 to 2023 active workforce table

Produces exactly these artifacts:
- `artifacts/workforce/urps_provider_snapshot.parquet` (provider-level, immutable)
- `artifacts/workforce/urps_counts_by_year.csv` (the aggregate count table)
- `artifacts/workforce/urps_manifest.json` (provenance for the above)

`urps_counts_by_year.csv` columns:

| column | meaning |
|---|---|
| `year` | measure year (2013 to 2023) |
| `board_pathway` | `abog_only`, `abu_net_new`, or `combined` where supported |
| `n_active` | active-in-year count under the active-in-year definition |
| `n_ever_certified` | ever-certified count for that pathway and year |
| `n_retired` | retired-by-that-year count |
| `snapshot_date` | date the underlying rosters were extracted |
| `source_sha256` | hash of the exact source inputs behind this row |
| `method_version` | version of the active-in-year / dedup method that produced it |

`urps_manifest.json` must specify:
- Exact source files
- SHA-256 hashes of each source file
- Snapshot date
- Active-in-year definition (the precise rule, not a label)
- ABOG/ABU deduplication rule
- Geographic scope
- Known limitations
- Git commit SHA of the isochrones code that produced the artifact

**Critical rule:** isochrones owns provider-level truth, but it is NOT the interface
used by every manuscript. It does not expose manuscript-specific projection
constants. Downstream code never imports isochrones internals; it consumes only the
three published artifacts above (and only through mufflyaccess).

---

## Charter: mufflyaccess - publish and validate the SSOT

**Owns the published analytical interface.** mufflyaccess is the only place a
consumer asks "what is the URPS count?" It does not build rosters; it certifies and
serves the number that isochrones built.

Responsibilities:
- Reading the canonical exported artifacts from isochrones
- Validating schema, hashes, counts, years, and cohort definitions
- Shipping a compact canonical workforce table
- Providing stable R functions
- Carrying provenance with every returned number
- Deprecating ambiguous constants

Primary API (the example return values below are the PRE-3.0.0 framing and are
SUPERSEDED, see the contract-3.0.0 reconciliation note in the section below;
current 2023 with-urology national = 1,306, not 1,339):

```r
mufflyaccess::urps_count(year = 2023L, include_urology = FALSE)  # pre-3.0.0 example only
mufflyaccess::urps_count(year = 2023L, include_urology = TRUE)   # pre-3.0.0 example only
```

Also provide:

```r
mufflyaccess::urps_counts()        # the full validated by-year, by-pathway table
mufflyaccess::urps_provenance()    # source files, hashes, dates, method, git SHA
mufflyaccess::validate_urps_ssot() # re-checks schema/hashes/counts; fails loudly on drift
```

Expected headline values: **SUPERSEDED by contract 3.0.0** (see the reconciliation
note below). The current 2023 `board_certified_active`, with-urology cells are
national **1,306** (1,027 ABOG + 279 ABU net-new) and CONUS **1,303**. The table
below is the retired pre-3.0.0 framing, kept only for lineage:

| cohort (RETIRED framing) | value |
|---|---|
| 2023 without urology (ABOG only) | 1,031 |
| 2023 with urology (ABOG + ABU) | 1,339 |
| ABU net-new | 308 |

Invariant under contract 3.0.0: `1027 + 279 == 1306`; `validate_urps_artifact()`
must assert it. (The retired `1031 + 308 == 1339` is history, not a target.)

**Three distinct time attributes, never collapsed into one ambiguous `year`:**

| attribute | example | meaning |
|---|---|---|
| measure year | 2023 | the year the count describes |
| source snapshot date | 2026-07-22 | when the rosters behind it were extracted |
| model baseline year | 2025 (if applicable) | the anchor year of a downstream projection |

Every returned number carries all three where they apply. A single `year` attribute
that silently means one of these is forbidden.

**Deprecate the ambiguous `*_2025` constants** (`URPS_COUNT_ABOG_ONLY_2025`,
`URPS_COUNT_ABOG_PLUS_ABU_2025`): keep them only as soft-deprecated aliases that emit
a deprecation warning and point to `urps_count()`, then remove in a later release.

**Critical rule:** mufflyaccess owns the published analytical interface, but it does
NOT independently rebuild provider rosters. If the number looks wrong, the fix is in
isochrones, re-published, and re-validated here, never patched into the package.

---

## Charter: cliff - consume the SSOT

**Owns projections, not the baseline.** cliff models what happens next; it may
transform the baseline into futures, but it cannot redefine it.

Responsibilities:
- Workforce projections
- Entrants and retirement modeling
- Scenario analyses
- Figures, tables, Shiny apps, and manuscript numbers
- Testing that its baseline agrees with mufflyaccess

It obtains baseline counts ONLY through the API:

```r
urps_without_urology <- mufflyaccess::urps_count(year = 2023L, include_urology = FALSE)
urps_with_urology    <- mufflyaccess::urps_count(year = 2023L, include_urology = TRUE)
```

Remove from cliff:
- Independent derivation of the national URPS count
- Hardcoded `1031`, `1339`, `1295`, `264`, or `308`
- A separate "canonical" reconciliation file used as authority
- Any code that reads raw ABOG or ABU rosters solely to establish the baseline

cliff may retain historical reconciliation documents, but they must be clearly
labeled **archival and non-authoritative**.

Add tests that fail if:
- the mufflyaccess baseline changes unexpectedly (pin the expected 2023 values), or
- a duplicate baseline literal (`1031`/`1339`/`1295`/`264`/`308`) is reintroduced
  anywhere outside an archival doc.

cliff depends on a **pinned release** of mufflyaccess for the 2023 baseline.

**Critical rule:** cliff may transform the baseline into projections, but it cannot
redefine the baseline.

---

## Charter: twostep - measure access (accessibility methodology)

**Owns the accessibility methodology, not the roster or the count.** twostep sits
beside cliff as a consumer of mufflyaccess, with a different analytical role: given
the canonical providers and the population, how accessible was care?

Responsibilities:
- E2SFCA calculations
- Catchment definitions
- Travel-time decay weights
- Supply-to-demand ratios
- Census denominator integration
- Geography aggregation
- Accessibility outputs by year, specialty, and travel-time band

It does NOT own:
- Raw ABOG or ABU roster cleaning
- National URPS baseline definitions
- Retirement classification
- ABOG/ABU deduplication
- Independent headline provider counts

**The isochrones vs twostep boundary (the names overlap; the roles do not):**

| | isochrones answers | twostep answers |
|---|---|---|
| question | which providers existed, were active, and where, in each year? | given those providers and the population, how accessible was care? |
| grain | one row per provider-year | one row per (year, specialty, geography, band) |
| canonical columns | `provider_id`, `specialty`, `board_pathway`, `year`, `active_in_year`, `latitude`, `longitude`, `provider_snapshot_version` | `year`, `specialty`, `geography`, `geoid`, `travel_time_band`, `provider_supply`, `population_demand`, `accessibility_score`, `method_version`, `provider_snapshot_version` |

**How twostep consumes (preferred design):** counts flow through mufflyaccess;
provider rows come directly from an isochrones release artifact.

```
isochrones -- provider artifact --> twostep
     |
     +-- count artifact --> mufflyaccess --> twostep
```

```r
providers      <- load_twostep_provider_input(specialty = "URPS", year = 2023L,
                                              include_urology = TRUE)
expected_count <- mufflyaccess::urps_count(year = 2023L, include_urology = TRUE)
stopifnot(dplyr::n_distinct(providers$provider_id) == expected_count)
```

This keeps mufflyaccess lightweight (it ships counts + provenance, not a large
provider-level dataset). An alternative, exposing provider rows through
`mufflyaccess::urps_providers()`, is warranted ONLY if several repos routinely need
provider-level rows and artifact retrieval is otherwise inconsistent; it makes the
package heavier and more tightly coupled to large data releases.

twostep must reconcile its provider input to the SSOT count and carry provider
provenance (`provider_snapshot_version`, `provider_source_sha256`) into its
accessibility outputs, but it VALIDATES the total, never redefines it.

Guarded by `tests/testthat/test-urps-consumer-contract.R` (reconcile to the SSOT +
provenance retention) and `tests/testthat/test-no-urps-count-derivation.R` (no
hardcoded or derived counts in twostep production code).

**Critical rule:** twostep may transform the canonical roster and population into
access measures, but it cannot redefine who, where, or how many.

---

## Reconciliation notes (open, must be resolved to make the charter true)

These are the points where the current repos do NOT yet satisfy the charter. They
are recorded here so the gap is explicit, not hidden.

> **CONTRACT 3.0.0 is current (2026-07-29). It supersedes v2.1.0 AND the earlier
> single-measure framing; the superseded numbers are history, not targets.** The
> current canonical 2023 `board_certified_active`, with-urology cells are:
> - national = **1,306**  (reconciliation: 1,027 ABOG + 279 ABU net-new)
> - CONUS = **1,303**
>
> **Retired v2.1.0 cells: 1,332 (national) / 1,329 (CONUS). These must NEVER appear
> as current expected values, anywhere.** Likewise the pre-v2.1 lines earlier in
> the mufflyaccess charter section ("2023 -> 1339", "1031 + 308 == 1339") are
> doubly-retired history. The **2025 `roster_snapshot`** value is NOT hand-assumed
> here (it is not necessarily 1,339); it must be read from the contract-3.0.0
> artifact or left pending until mufflyaccess 0.7.0 exposes it. twostep's consumer
> tests (`test-urps-consumer-contract.R`) pin 1,306 / 1,303 and skip until
> mufflyaccess 0.7.0 (contract 3.0.0) is installed.

1. **The 2023 baseline is a target, not yet a validated artifact.** These figures
   are the specification to build toward. isochrones has not yet emitted
   `artifacts/workforce/urps_counts_by_year.csv` with a 2023 row, and mufflyaccess
   has not shipped `urps_count()` at all. Until both exist, the numbers must be
   validated against the artifact before any manuscript cites them.

2. **The currently frozen constants are 2025, not 2023.** mufflyaccess currently
   ships `URPS_COUNT_ABOG_ONLY_2025 = 1031`, `URPS_COUNT_ABOG_PLUS_ABU_2025 = 1295`
   (ABU net-new 264). Under this charter those become soft-deprecated aliases and
   the canonical values move to the 2023 measure year (1031 / 1339 / 308). The
   with-urology count and net-new differ between the two years by design; they are
   different quantities, distinguished by the measure-year attribute, not a
   correction.

3. **twostep is vendored, not dependent.** For publication, the shared access
   constants were vendored into twostep so it builds without the private
   mufflyaccess repo. That is a deliberate exception to the runtime-dependency
   arrow, justified only while mufflyaccess is private. The charter's arrow into
   twostep becomes literally true once mufflyaccess is installable by consumers
   (public / r-universe / CRAN); at that point twostep should either re-depend on
   the package or keep the vendored copy behind a validated `validate_*_ssot()`
   equality test. The workforce baseline is unaffected (twostep never consumed it).

4. **mufflyaccess must be installable by consumers for the arrow to hold.** cliff
   pinning a release, and any consumer calling `urps_count()`, both require the
   package to be reachable. Making mufflyaccess installable (public or a private
   registry the consumers can authenticate to) is a precondition of this contract.
