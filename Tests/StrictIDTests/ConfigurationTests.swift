import Foundation
import Testing

@testable import StrictID

// `ID.bootstrap` installs process-wide state, and tests run in parallel — so no test here installs
// a configuration that differs from the default one. The rules of bootstrapping are exercised on a
// local `ConfigurationStore` instead (which is exactly why that state machine is a value type), and
// the process-wide side is checked through its defaults plus the no-op bootstrap that can't disturb
// anybody. Per-call `alphabet:` / `mode:` arguments cover everything else without globals.

@Suite("Configuration")
struct ConfigurationTests {

    // MARK: - Configuration values

    @Test("A default configuration is the built-in alphabet and the modern separator")
    func defaults() {
        let configuration = ID.Configuration()
        #expect(configuration.alphabet == .default)
        #expect(configuration.separatorMode == .modern)
    }

    @Test("A seed permutes the alphabet as the configuration is built")
    func seedIsAppliedOnInit() throws {
        let seeded = ID.Configuration(seed: "hunter2")
        #expect(seeded.alphabet == ID.Alphabet.default.shuffled(seed: "hunter2"))
        #expect(seeded.alphabet != .default)

        // Seeding a specific alphabet permutes that one, not the built-in default.
        let hex = try ID.Alphabet("0123456789abcdef")
        let seededHex = ID.Configuration(alphabet: hex, seed: "hunter2")
        #expect(seededHex.alphabet == hex.shuffled(seed: "hunter2"))
        #expect(Set(seededHex.alphabet.symbols) == Set(hex.symbols))

        // No seed means the alphabet is stored as handed over.
        #expect(ID.Configuration(alphabet: hex).alphabet == hex)
    }

    @Test("Configurations compare by what they do, so the same seed makes the same configuration")
    func equality() {
        #expect(ID.Configuration(seed: "a") == ID.Configuration(seed: "a"))
        #expect(ID.Configuration(seed: "a") != ID.Configuration(seed: "b"))
        #expect(ID.Configuration(seed: "a") != ID.Configuration())
        #expect(ID.Configuration(separatorMode: .legacy) != ID.Configuration(separatorMode: .modern))
    }

    // MARK: - Bootstrap rules

    @Test("The first bootstrap installs the configuration")
    func firstBootstrapInstalls() throws {
        var store = ID.ConfigurationStore()
        #expect(store.isBootstrapped == false)
        #expect(store.configuration == ID.Configuration())

        let configuration = ID.Configuration(seed: "hunter2", separatorMode: .legacy)
        try store.bootstrap(configuration, replacingExisting: false)

        #expect(store.isBootstrapped)
        #expect(store.configuration == configuration)
    }

    @Test("Bootstrapping the same configuration again is a no-op")
    func repeatedIdenticalBootstrapIsFine() throws {
        var store = ID.ConfigurationStore()
        let configuration = ID.Configuration(seed: "hunter2")

        try store.bootstrap(configuration, replacingExisting: false)
        try store.bootstrap(configuration, replacingExisting: false)
        try store.bootstrap(ID.Configuration(seed: "hunter2"), replacingExisting: false)

        #expect(store.configuration == configuration)
    }

    @Test("A conflicting bootstrap throws instead of quietly changing the format")
    func conflictingBootstrapThrows() throws {
        var store = ID.ConfigurationStore()
        try store.bootstrap(ID.Configuration(seed: "hunter2"), replacingExisting: false)

        #expect(throws: ID.BootstrapError.AlreadyBootstrapped) {
            try store.bootstrap(ID.Configuration(seed: "different"), replacingExisting: false)
        }
        #expect(throws: ID.BootstrapError.AlreadyBootstrapped) {
            try store.bootstrap(ID.Configuration(separatorMode: .legacy), replacingExisting: false)
        }
        #expect(throws: ID.BootstrapError.AlreadyBootstrapped) {
            try store.bootstrap(ID.Configuration(), replacingExisting: false)
        }

        #expect(store.configuration == ID.Configuration(seed: "hunter2"), "the installed configuration stands")
    }

    @Test("replacingExisting: true is the deliberate way through")
    func replacingExistingReplaces() throws {
        var store = ID.ConfigurationStore()
        try store.bootstrap(ID.Configuration(seed: "hunter2"), replacingExisting: false)

        let replacement = ID.Configuration(separatorMode: .strictLegacy)
        try store.bootstrap(replacement, replacingExisting: true)

        #expect(store.configuration == replacement)
        #expect(store.isBootstrapped)

        // And the gate is armed again for whatever comes next.
        #expect(throws: ID.BootstrapError.AlreadyBootstrapped) {
            try store.bootstrap(ID.Configuration(), replacingExisting: false)
        }
    }

    @Test("A first bootstrap with replacingExisting: true is fine too")
    func replacingWithoutPriorBootstrap() throws {
        var store = ID.ConfigurationStore()
        let configuration = ID.Configuration(separatorMode: .legacy)

        try store.bootstrap(configuration, replacingExisting: true)
        #expect(store.configuration == configuration)
    }

    // MARK: - The process-wide configuration

    @Test("Nothing is bootstrapped by default, and the defaults are the historical format")
    func processWideDefaults() {
        #expect(ID.configuration == ID.Configuration())
        #expect(ID.configuration.alphabet == .default)
        #expect(ID.separatorMode == .modern)
    }

    @Test("The alphabet accessors report the installed alphabet")
    func alphabetAccessors() {
        #expect(ID.alphabet == ID.configuration.alphabet.string)
        #expect(ID.rawAlphabet == ID.configuration.alphabet.symbols)
        #expect(ID.alphabetSize == ID.configuration.alphabet.count)
        #expect(ID.fullAlphabet == ID.alphabet + "_")
        #expect(ID.fullAlphabetSize == ID.alphabetSize + 1)
        #expect(ID.alphabet == "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    }

    @Test("Bootstrapping the configuration that's already installed is accepted")
    func processWideNoOpBootstrap() throws {
        // Safe under parallel tests precisely because it changes nothing.
        try ID.bootstrap(ID.configuration)
        try ID.bootstrap(alphabet: .default, separatorMode: .modern)

        #expect(ID.configuration == ID.Configuration())
    }

    @Test("The convenience bootstrap builds the same configuration as the value one")
    func convenienceMatchesValueForm() throws {
        var fromParts = ID.ConfigurationStore()
        var fromValue = ID.ConfigurationStore()

        try fromParts.bootstrap(
            ID.Configuration(alphabet: .default, seed: "hunter2", separatorMode: .legacy),
            replacingExisting: false
        )
        try fromValue.bootstrap(
            ID.Configuration(alphabet: ID.Alphabet.default.shuffled(seed: "hunter2"), separatorMode: .legacy),
            replacingExisting: false
        )

        #expect(fromParts.configuration == fromValue.configuration)
    }

    // MARK: - Per-call arguments over the installed configuration

    @Test("Per-call arguments override the installed configuration one dimension at a time")
    func perCallOverrides() throws {
        let alphabet = try ID.Alphabet("0123456789abcdef")

        // Alphabet overridden, separator left to the installed configuration (modern).
        let hexModern = try ID(shardNumber: 1337, identifier: 42, entityKind: "P", alphabet: alphabet)
        #expect(hexModern.stringValue.hasPrefix("P_"))
        #expect(!hexModern.stringValue.hasPrefix("P__"))
        #expect(hexModern.stringValue.dropFirst(2).allSatisfy { alphabet.symbols.contains($0) })

        // Separator overridden, alphabet left to the installed configuration (the built-in one).
        let defaultLegacy = try ID(shardNumber: 1337, identifier: 42, entityKind: "P", mode: .legacy)
        #expect(defaultLegacy.stringValue == "P__zuYa75Z5")

        // Both overridden.
        let hexLegacy = try ID(
            shardNumber: 1337,
            identifier: 42,
            entityKind: "P",
            alphabet: alphabet,
            mode: .legacy
        )
        #expect(hexLegacy.stringValue.hasPrefix("P__"))
        #expect(try ID.parse(input: hexLegacy.stringValue, alphabet: alphabet, mode: .strictLegacy) == hexLegacy)
        #expect(hexLegacy == hexModern, "same numbers, two spellings")
    }

    @Test("IDOf.parse passes the alphabet through as well")
    func idOfHonoursAlphabet() throws {
        struct Alpha: IDPrefixable {
            enum Prefix: String { case alpha = "A" }
            static let IDPrefix: Prefix = .alpha
        }

        let alphabet = try ID.Alphabet("0123456789abcdef")
        let id = try ID(shardNumber: 1, identifier: 1, entityKind: "A", alphabet: alphabet)

        let parsed = try IDOf<Alpha>.parse(input: id.stringValue, alphabet: alphabet)
        #expect(parsed.base == id)

        #expect(throws: (any Error).self, "the built-in alphabet can't read a hex body") {
            try IDOf<Alpha>.parse(input: "A_ffffffffff", alphabet: .default)
        }
    }
}
