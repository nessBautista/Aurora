import ArgumentParser

@main
struct Aurora: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aurora",
        version: auroraVersion,
        subcommands: [Hello.self]
    )
}

struct Hello: ParsableCommand {
    @Argument(help: "Name to greet.")
    var name: String

    func run() {
        print(greet(name: name))
    }
}
