
import AuroraAgent

enum Container {
    /// Construct the production `Agent`. Today this is a passthrough to
    /// `AgentFactory.makeDefault()
    static func makeAgent() async -> Agent {
        await AgentFactory.makeDefault()
    }
}
