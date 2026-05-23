import ArgumentParser

@main
struct Aurora: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aurora",
        version: auroraVersion,
        subcommands: [
            Hello.self,
            AuthCommand.self,
            ChatCommand.self,
        ]
    )
}

struct Hello: ParsableCommand {
    @Argument(help: "Name to greet.")
    var name: String

    func run() {
        print(greet(name: name))
    }
}
