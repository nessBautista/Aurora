import ArgumentParser
import AuroraAgent
import Foundation

struct ChatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Send a single prompt to the model and print the response."
    )

    @Argument(help: "The prompt to send.")
    var prompt: String

    @Option(name: .long, help: "Override the LLM provider for this call: \(providerList)")
    var provider: String?

    func run() async throws {
        // A typo'd `--provider` is a ValidationError here (matches `auth set`).
        let override = try provider.map(parseProvider)

        let agent: Agent
        do {
            agent = try await Container.makeAgent(providerOverride: override)
        } catch let error as AgentAuthError {
            // No provider chosen anywhere — point the user at the fix.
            StdIO.writeStderr("Error: \(error.errorDescription ?? "no provider selected").\n")
            throw ExitCode.failure
        }

        // Banner reads agent.providerInfo, whose apiKeySource field
        // comes from the pre-load snapshot Config captured during
        // makeDefault → Config.load(). So the banner still shows
        // "keychain (Touch ID)" even though env now has the key copied
        // from keychain.
        printBanner(agent.providerInfo)

        do {
            print(try await agent.chat(prompt))
        } catch {
            // If the user simply hasn't set up a key for the RESOLVED
            // provider, give them a setup hint instead of the raw API auth
            // error. `apiKeySource == "missing"` is the provider-agnostic
            // signal (no env / keychain / .env key anywhere).
            let info = agent.providerInfo
            if info.apiKeySource == "missing" {
                StdIO.writeStderr(
                    "Error: no API key configured for \(info.providerName). " +
                    "Run `aurora auth set \(info.providerName.lowercased())` to store one.\n"
                )
            } else {
                StdIO.writeStderr("Error: \(error.localizedDescription)\n")
            }
            throw ExitCode.failure
        }
    }

    private func printBanner(_ info: ProviderInfo) {
        let lines = [
            "Provider:  \(info.providerName)",
            "Model:     \(info.modelId)",
            "API key:   \(info.apiKeySource)",
        ]
        let banner = "─── aurora ──────────────────\n"
            + lines.map { "  \($0)" }.joined(separator: "\n")
            + "\n─────────────────────────────"
        StdIO.writeStderr(banner + "\n")
    }
}
