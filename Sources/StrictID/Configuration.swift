extension ID {
    /// Everything about the string format that a deployment gets to choose: the symbols bodies are
    /// spelled with, and which prefix separator is rendered and accepted.
    ///
    /// Install one at startup with `ID.bootstrap(_:replacingExisting:)`. Every API that doesn't take
    /// an explicit `alphabet:` or `mode:` argument reads the installed configuration, so passing
    /// those arguments overrides one dimension of it for a single call — which is how a process
    /// handles more than one format at a time.
    public struct Configuration: Sendable, Equatable {
        public var alphabet: Alphabet
        public var separatorMode: SeparatorMode

        /// - Parameters:
        ///   - alphabet: the symbols bodies are spelled with.
        ///   - seed: when given, `alphabet` is stored permuted by `Alphabet.shuffled(seed:)`. The
        ///     seed itself is not retained anywhere — only the resulting order is, and the seed
        ///     can't be recovered from it.
        ///   - separatorMode: which prefix separator is rendered and accepted.
        public init(
            alphabet: Alphabet = .default,
            seed: String? = nil,
            separatorMode: SeparatorMode = .modern
        ) {
            self.alphabet = seed.map { alphabet.shuffled(seed: $0) } ?? alphabet
            self.separatorMode = separatorMode
        }
    }

    public enum BootstrapError: Error {
        /// A different configuration is already installed. Bootstrap once, at startup — or pass
        /// `replacingExisting: true` if replacing it mid-flight really is what you mean.
        case AlreadyBootstrapped
    }

    /// The bootstrap state machine, kept as a value type so its rules can be tested without
    /// touching the process-wide instance.
    internal struct ConfigurationStore {
        internal private(set) var configuration: Configuration
        internal private(set) var isBootstrapped: Bool

        internal init(_ configuration: Configuration = .init()) {
            self.configuration = configuration
            self.isBootstrapped = false
        }

        /// Installs `configuration`. Re-installing the very same one is a no-op rather than an
        /// error — it can't surprise anybody — while a conflicting one needs `replacingExisting`.
        internal mutating func bootstrap(
            _ configuration: Configuration,
            replacingExisting: Bool
        ) throws(BootstrapError) {
            if self.isBootstrapped, !replacingExisting, configuration != self.configuration {
                throw BootstrapError.AlreadyBootstrapped
            }

            self.configuration = configuration
            self.isBootstrapped = true
        }
    }

    /// Process-wide configuration state. Deliberately unsynchronized (`nonisolated(unsafe)`): it's
    /// written once at startup, before any identifier exists, and only read afterwards.
    internal nonisolated(unsafe) static var store = ConfigurationStore()

    /// The installed configuration — the default one until `bootstrap` says otherwise. Read-only on
    /// purpose: changing the format is what `bootstrap` is for.
    public static var configuration: Configuration { Self.store.configuration }

    /// The installed separator mode, i.e. `configuration.separatorMode`.
    public static var separatorMode: SeparatorMode { Self.configuration.separatorMode }

    /// Installs the configuration for this process. Call it once, at startup, before creating or
    /// parsing any identifier.
    ///
    /// Bootstrapping the same configuration again does nothing. A *different* one throws
    /// `BootstrapError.AlreadyBootstrapped`, because identifiers already handed out would become
    /// unreadable — pass `replacingExisting: true` to say that you know and mean it.
    public static func bootstrap(
        _ configuration: Configuration,
        replacingExisting: Bool = false
    ) throws(BootstrapError) {
        try Self.store.bootstrap(configuration, replacingExisting: replacingExisting)
    }

    /// Installs a configuration built from its parts. Unmentioned parts take their default value
    /// (not the currently installed one), the same as `Configuration.init`.
    ///
    /// ```swift
    /// // built-in alphabet, permuted by a secret seed delivered at runtime
    /// try ID.bootstrap(seed: ProcessInfo.processInfo.environment["STRICT_ID_SEED"])
    ///
    /// // a smaller alphabet of one's own, in the order given, plus the legacy separator
    /// try ID.bootstrap(alphabet: try .init("346789ABCDEFGHJKMNPQRTVWXY"), separatorMode: .legacy)
    /// ```
    public static func bootstrap(
        alphabet: Alphabet = .default,
        seed: String? = nil,
        separatorMode: SeparatorMode = .modern,
        replacingExisting: Bool = false
    ) throws(BootstrapError) {
        try Self.bootstrap(
            Configuration(alphabet: alphabet, seed: seed, separatorMode: separatorMode),
            replacingExisting: replacingExisting
        )
    }
}
