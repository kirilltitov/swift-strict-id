# StrictID

Strictly typed, sharding-aware string identifiers for Swift: compact, opaque,
self-contained, and impossible to mix up between entity types at compile time.

```swift
let id = try ID(shardNumber: 1337, identifier: 42, entityKind: "O")
print(id) // "O_nqZUh6AO"
```

A Go implementation of the same wire format is available at
[strictid](https://github.com/kirilltitov/strictid) — the two libraries exchange IDs across service
boundaries in both directions out of the box. The Go one still *renders* the legacy separator
(see [Separator formats](#separator-formats-and-compatibility)), so if byte-identical output on both
sides matters to you, set `ID.separatorMode = .legacy` here until it catches up.

## Why

In a sharded system with numeric auto-increment keys, you usually need all of the following
at once:

- **Avoid confusing entities** — `User#42` and `Order#42` colliding on the same numeric ID has
  historically been a source of bugs and vulnerabilities (IDOR, accidental joins on a bare
  number instead of a typed key).
- **Avoid leaking infrastructure** — an ID like `42` in shard `3` tells an outside observer how
  sharding works, roughly how much data exists, and the creation order of records.
- **Never lose the shard** — when moving from a flat auto-increment to a sharded schema, the
  shard number has to live somewhere, ideally travelling with the identifier itself rather than
  as a separate field.
- **Tell identical auto-increments of different entities apart visually** — so `O_xxxx` and
  `U_xxxx` don't look like the same ID with a different label, and a copy-paste mistake is
  obvious at a glance.

`StrictID` solves all four with a single format: `{PREFIX}_{sqids}`.

## Format

The string representation of an identifier has two parts, separated by a single underscore:

```
O_nqZUh6AO
│ └──────── sqids body
└────────── prefix (entityKind)
```

**Prefix** (`entityKind`) — 1 or 2 characters denoting the entity type (`O` for Organization, `U`
for User, and so on), followed by one underscore. The underscore isn't part of the sqids alphabet,
so the first underscore run in the string always marks the end of the prefix and the start of the
body — the boundary is unambiguous to locate whatever the prefix length. (Identifiers generated
before the format change pad that separator instead; see
[Separator formats](#separator-formats-and-compatibility).)

**Body** — the result of encoding a tuple of **three** `Int64` values (`rawValues`) with
[sqids](https://github.com/sqids/sqids-swift):

```swift
[shardNumber, bytesSum, identifier]
```

| Component     | Meaning                                                                |
|---------------|-------------------------------------------------------------------------|
| `shardNumber` | The shard the entity was created in.                                   |
| `bytesSum`    | Sum of the UTF-8 bytes of `entityKind`. Computed automatically.        |
| `identifier`  | The auto-increment (or other numeric ID) within the shard.             |

The middle element, `bytesSum`, isn't data on its own — it's a "salt" derived from the entity
type. Its sole purpose is to make encoded strings of different entity types look visually
distinct even when `shardNumber` and `identifier` are identical: sqids is a reversible encoding,
so without this salt an `Organization` with `shardNumber=1, identifier=1` and a `User` with
`shardNumber=1, identifier=1` would encode to the exact same body, differing only by prefix.
`bytesSum` removes that last coincidence too.

The sqids alphabet (`ID.alphabet`) is 62 characters: `0-9` and Latin letters in both cases,
sorted. The underscore is not part of the alphabet and is reserved for prefix separators, so an
ID body can never accidentally contain `_` and create ambiguity while parsing.

## Separator formats and compatibility

The format used to pad the prefix zone with underscores to a fixed `ID.prefixSize` (3) characters,
so a one-character prefix was followed by **two** of them: `O__nqZUh6AO`. Back when every
identifier was a fixed length, that kept the layout aligned; identifiers are variable-length now, so
the padding buys nothing and the current format separates prefix from body with exactly one
underscore.

Only one-character prefixes are affected. A two-character prefix (`PL_lDm0uwOeWd1aU9uIj`) and an
external-UUID prefix (`_U_brd1jN`) filled the prefix zone by themselves and are byte-identical in
both formats.

`ID.SeparatorMode` decides which format is rendered and which ones `parse` accepts:

| Mode                | Renders       | Accepts     |
|---------------------|---------------|-------------|
| `.strictModern`     | `O_nqZUh6AO`  | modern only |
| `.modern` (default) | `O_nqZUh6AO`  | both        |
| `.legacy`           | `O__nqZUh6AO` | both        |
| `.strictLegacy`     | `O__nqZUh6AO` | legacy only |

Anything that matches neither format — three underscores in a row, say — is rejected in every mode
with `ID.E.InvalidPrefixSeparator`, as is a format a strict mode doesn't accept.

The mode is a process-wide switch, with a per-call override wherever one process has to deal with
both formats at once:

```swift
ID.separatorMode = .legacy  // once, at startup, before any ID is created or parsed

let id = try ID(shardNumber: 7, identifier: 12345, entityKind: "O", mode: .modern)
let parsed = try ID.parse(input: incoming, mode: .strictLegacy)
```

The four modes form a ladder for rolling a fleet over without a flag day: `.strictLegacy` →
`.legacy` → `.modern` → `.strictModern`. Teach every reader to accept both formats first, then flip
the writers over, then — once no legacy string is left anywhere — optionally tighten back down so a
stale one shows up as an error instead of passing silently. Each rung is deployable while peers sit
one rung behind.

Parsing never rewrites what it was handed: `stringValue` keeps the exact input, so an identifier
read in the legacy format is written back out in the legacy format, `Codable` included. Equality and
hashing, on the other hand, are based on `(entityKind, rawValues)` — the identifier's identity, not
its spelling — so the two forms of one identifier compare equal and mixed-format data doesn't grow
phantom duplicates in a `Set` or a dictionary key:

```swift
let a = try ID.parse(input: "P__zuYa75Z5")  // legacy spelling
let b = try ID.parse(input: "P_zuYa75Z5")   // modern spelling
a == b                          // true — same shard, same identifier, same entity kind
a.stringValue == b.stringValue  // false — the strings differ, and each is preserved as given
```

To rewrite a legacy identifier in the modern format (normalizing data at rest, for instance),
re-render it from its parts:

```swift
let modern = try ID(rawValues: legacy.rawValues, entityKind: legacy.entityKind, mode: .modern)
```

## Quick start

### Installation

```swift
// Package.swift
dependencies: [
    .package(url: "<this repository's URL>", from: "1.0.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [.product(name: "StrictID", package: "swift-strict-id")]
    ),
]
```

### Creating and parsing

```swift
import StrictID

let id = try ID(shardNumber: 7, identifier: 12345, entityKind: "O")
id.stringValue   // "O_ApB7Jf7b0"
id.shardNumber   // 7
id.identifier    // 12345
id.entityKind    // "O"

let parsed = try ID.parse(input: id.stringValue)
parsed == id     // true
```

`ID` also conforms to `LosslessStringConvertible` (`ID(string)` → `ID?`) and `Codable` (encoded
and decoded as a plain string) — both paths funnel through the same `parse`.

### Examples

Shards stay small in practice (dozens, maybe hundreds), while identifiers routinely climb into
the billions or trillions as an auto-increment ages. The table below shows the same shard and
entity kind (`shardNumber: 7, entityKind: "O"`) across identifier orders of magnitude, then the
same identifier across a few different shards, so both axes are visible independently.

| `shardNumber` | `identifier`        | `stringValue`                |
|--------------:|---------------------:|-------------------------------|
| 7             | 1                     | `O_O9wc4uL`                   |
| 7             | 10                    | `O_8tPdMxW`                   |
| 7             | 100                   | `O_jrcJv6k5`                  |
| 7             | 1,000                 | `O_5fAlwHDk`                  |
| 7             | 10,000                | `O_vx78WjTS2`                 |
| 7             | 100,000               | `O_ApB7JfS48`                 |
| 7             | 1,000,000             | `O_CMbGweZxrR`                |
| 7             | 10,000,000            | `O_Z1FenHuAmw`                |
| 7             | 100,000,000           | `O_dqrtiL1wutF`               |
| 7             | 1,000,000,000         | `O_qaQKycvX1B7j`              |
| 7             | 10,000,000,000        | `O_1djJ92hZVGpV`              |
| 7             | 100,000,000,000       | `O_Jb1zlSQO4Epif`             |
| 7             | 1,000,000,000,000     | `O_cmNTwhNkZHKUQ`             |
| 7             | 9,007,199,254,740,991 (`ID.maxIdentifier`) | `O_ApB7JfM9KdGQbQ5` |

| `shardNumber` | `identifier` | `stringValue`         |
|--------------:|-------------:|------------------------|
| 0             | 999,999      | `U_2lS5c0VxlU`         |
| 1             | 999,999      | `U_5CAlyHRkBe`         |
| 7             | 999,999      | `U_ieOe2l8dmM`         |
| 42            | 999,999      | `U_ImLcy0kYBX`         |
| 128           | 999,999      | `U_EOXT4j1NkJw`        |

Note how every string keeps the same `minLength` floor (`ID.minLength`, 6 characters for the
body) and grows only as needed for larger numbers — and how none of them resemble one another
despite sharing an entity kind and differing by just one field.

### Type-safe identifiers: `IDOf<T>`

A bare `ID` doesn't stop you from passing one entity's identifier where another is expected —
there's only one `ID` type. `IDOf<T>` closes that gap: it's a wrapper over `ID`, parameterized by
the entity type, validating the prefix match at creation time.

```swift
enum OrganizationPrefix: String { case organization = "O" }

struct Organization: IDPrefixable {
    typealias IDPrefixEnum = OrganizationPrefix
    static let IDPrefix: OrganizationPrefix = .organization
}

enum UserPrefix: String { case user = "U" }

struct User: IDPrefixable {
    typealias IDPrefixEnum = UserPrefix
    static let IDPrefix: UserPrefix = .user
}

let orgID = try ID(shardNumber: 1, identifier: 1, entityKind: "O").of(Organization.self)
let userID = try ID(shardNumber: 1, identifier: 1, entityKind: "U").of(User.self)

// orgID has type IDOf<Organization>, userID has type IDOf<User>.
// The compiler won't let one be passed where the other is expected, even if function
// signatures are structurally identical.
```

Wrapping an `ID` with a mismatched prefix — `IDOf<Organization>(base:)` — throws
`IDOf<Organization>.E.WrongIdPrefix`. Using a `RawRepresentable` enum instead of a bare string in
`IDPrefixable` is deliberate: adding a new entity is forced to cascade through the type system as
part of declaring its prefix, rather than as a stray string somewhere in the code.

### External UUIDs

Sometimes you need to accept a "foreign" identifier — a UUID from an external system — and
represent it in the same `StrictID` format without losing a single bit:

```swift
let uuid = UUID()
let wrapped = try ID(externalUUID: uuid)      // default prefix "_U"
wrapped.externalUUID                          // Optional(uuid) — exact inverse

let custom = try ID(externalUUID: uuid, entityKind: "_X")
```

For example, `f47ac10b-58cc-4372-b567-0e02b2c3d479` wraps losslessly into
`_U_fa33IoDBnFpwLjvPyqgSHXkrU`, decomposing into `rawValues =
[2351607909684651, 4005552, 1985729588876409]` — and `id.externalUUID` reconstructs the exact
original UUID from that triple.

The 128 bits of a UUID fit losslessly into the same three `Int64` values: the container yields
63+63+53 = 179 usable bits under the real field constraints (`shardNumber`/`bytesSum`-slot ≥ 0,
`identifier` ≤ 2⁵³−1). The marker that says "this is a wrapped UUID" is the reserved `_` as the
first character of the prefix; regular identifiers never start with `_`, so the two parsing
branches (regular ID vs. external UUID) never overlap.

## Constraints

- `identifier` is capped at `ID.maxIdentifier` = `9_007_199_254_740_991` (2⁵³−1) — matching the
  exact-integer range of JS/JSON `Number`.
- `entityKind` must be exactly 1 or 2 characters (aside from the reserved external-UUID marker).
- The minimum encoded body length is `ID.minLength` = 6 characters (via sqids padding),
  regardless of the actual `rawValues`.
- Prefix and body are separated by exactly one underscore — or by the legacy padding, depending on
  the [separator mode](#separator-formats-and-compatibility). Any other separator is rejected.

## Development

```bash
swift test
```

## License

Apache License 2.0 — see [LICENSE](LICENSE).
