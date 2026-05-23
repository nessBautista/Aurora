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

    func run() async throws {
        let agent = await Container.makeAgent()

        // Banner reads agent.providerInfo, whose apiKeySource field
        // comes from the pre-load snapshot Config captured during
        // makeDefault → Config.load(). So the banner still shows
        // "keychain (Touch ID)" even though env now has the key copied
        // from keychain.
        printBanner(agent.providerInfo)

        do {
            print(try await agent.chat(prompt))
        } catch {
            // If the user simply hasn't set up a key, give them a setup
            // hint instead of the raw API auth error.
            if AgentAuth.keyStatus(.anthropic) == .missing {
                StdIO.writeStderr(
                    "Error: no API key configured. " +
                    "Run `aurora auth set anthropic` to store one.\n"
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
