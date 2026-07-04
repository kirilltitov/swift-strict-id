# StrictID

Strictly typed, sharding-aware string identifiers for Swift: compact, opaque,
self-contained, and impossible to mix up between entity types at compile time.

```swift
let id = try ID(shardNumber: 1337, identifier: 42, entityKind: "O")
print(id) // "O__nqZUh6AO"
```

A Go implementation of the same wire format is available at
[strictid](https://github.com/kirilltitov/strictid) — both libraries produce byte-identical
strings for the same input and can freely exchange IDs across service boundaries.

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
- **Tell identical auto-increments of different entities apart visually** — so `O__xxxx` and
  `U__xxxx` don't look like the same ID with a different label, and a copy-paste mistake is
  obvious at a glance.

`StrictID` solves all four with a single format: `{PREFIX}_{sqids}`.

## Format

The string representation of an identifier has two parts, separated by underscores:

```
O__nqZUh6AO
└┘ └───────┘
prefix  sqids body
```

**Prefix** (`entityKind`) — 1 or 2 characters denoting the entity type (`O` for Organization, `U`
for User, and so on). The prefix zone always occupies exactly `ID.prefixSize` (3) characters: a
single-character prefix is padded with two underscores (`O__`), a two-character prefix with one
(`PL_`). This makes the boundary between prefix and body unambiguous to locate while parsing,
regardless of prefix length.

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
id.stringValue   // "O__..."
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
| 7             | 1                     | `O__O9wc4uL`                  |
| 7             | 10                    | `O__8tPdMxW`                  |
| 7             | 100                   | `O__jrcJv6k5`                 |
| 7             | 1,000                 | `O__5fAlwHDk`                 |
| 7             | 10,000                | `O__vx78WjTS2`                |
| 7             | 100,000               | `O__ApB7JfS48`                |
| 7             | 1,000,000             | `O__CMbGweZxrR`               |
| 7             | 10,000,000            | `O__Z1FenHuAmw`               |
| 7             | 100,000,000           | `O__dqrtiL1wutF`              |
| 7             | 1,000,000,000         | `O__qaQKycvX1B7j`             |
| 7             | 10,000,000,000        | `O__1djJ92hZVGpV`             |
| 7             | 100,000,000,000       | `O__Jb1zlSQO4Epif`            |
| 7             | 1,000,000,000,000     | `O__cmNTwhNkZHKUQ`            |
| 7             | 9,007,199,254,740,991 (`ID.maxIdentifier`) | `O__ApB7JfM9KdGQbQ5` |

| `shardNumber` | `identifier` | `stringValue`         |
|--------------:|-------------:|------------------------|
| 0             | 999,999      | `U__2lS5c0VxlU`        |
| 1             | 999,999      | `U__5CAlyHRkBe`        |
| 7             | 999,999      | `U__ieOe2l8dmM`        |
| 42            | 999,999      | `U__ImLcy0kYBX`        |
| 128           | 999,999      | `U__EOXT4j1NkJw`       |

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

## Development

```bash
swift test
```

## License

Apache License 2.0 — see [LICENSE](LICENSE).
