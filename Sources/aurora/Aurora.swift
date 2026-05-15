import ArgumentParser

@main
struct Aurora: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aurora",
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
