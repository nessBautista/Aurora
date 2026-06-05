import ArgumentParser
import AuroraAgent
import Foundation

struct AuthCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "auth",
        abstract: "Manage Aurora's stored API Keys",
        subcommands: [Set.self, Status.self, Clear.self, Use.self]
    )
    
    
    // MARK: - set

    struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Store an API key in the macOS keychain (Touch ID protected)."
        )

        @Argument(help: "Provider: \(providerList)")
        var providerName: String

        func run() throws {
            // validate provider
            let provider = try parseProvider(providerName)
            // request api key
            StdIO.writeStderr("\(provider.rawValue.capitalized) API key: ")
            guard let key = StdIO.readPasswordSilently(), !key.isEmpty else {
                StdIO.writeStderr("(empty — aborted)\n")
                throw ExitCode.failure
            }
            // store key
            try AgentAuth.setKey(provider, key)
            print("✓ Stored in keychain (service: aurora, account: \(provider.rawValue)_api_key)")
            print("  Touch ID will be required to read it.")
        }
    }

    // MARK: - status

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show where each provider's API key is loaded from."
        )

        func run() {
            for provider in AgentAuth.Provider.allCases {
                let label = "\(provider.rawValue)_api_key:"
                let source: String
                switch AgentAuth.keyStatus(provider) {
                case .env:      source = "process env (\(provider.rawValue.uppercased())_API_KEY set)"
                case .keychain: source = "keychain (Touch ID protected)"
                case .envFile:  source = ".env file (plaintext)"
                case .missing:  source = "missing — run `aurora auth set \(provider.rawValue)`"
                }
                print("\(label.padding(toLength: 22, withPad: " ", startingAt: 0)) \(source)")
            }
        }
    }

    // MARK: - clear

    struct Clear: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "clear",
            abstract: "Remove a stored API key from the keychain."
        )

        @Argument(help: "Provider: \(providerList)")
        var providerName: String

        func run() throws {
            let provider = try parseProvider(providerName)
            AgentAuth.clearKey(provider)
            print("✓ Removed from keychain.")
        }
    }

    // MARK: - use

    struct Use: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "use",
            abstract: "Set the default provider for `aurora chat`."
        )

        @Argument(help: "Provider: \(providerList)")
        var providerName: String

        func run() throws {
            let provider = try parseProvider(providerName)
            AgentAuth.setActiveProvider(provider)
            print("✓ Default provider set to \(provider.rawValue). "
                + "`aurora chat` will use it unless overridden by --provider or LLM_PROVIDER.")
        }
    }
}


/// Human-readable provider list for help text.
let providerList = AgentAuth.Provider.allCases.map(\.rawValue).joined(separator: " | ")

/// Centralized provider parsing (shared by the auth subcommands and `chat`).
func parseProvider(_ name: String) throws -> AgentAuth.Provider {
    guard let provider = AgentAuth.Provider(rawValue: name.lowercased()) else {
        let valid = AgentAuth.Provider.allCases.map(\.rawValue).joined(separator: ", ")
        throw ValidationError("Unknown provider '\(name)'. Valid: \(valid)")
    }
    return provider
}
