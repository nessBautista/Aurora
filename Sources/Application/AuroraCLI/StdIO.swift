import Foundation

enum StdIO {

    /// Pipeable stdout matters from day one — diagnostics go to stderr
    /// so the user can `aurora chat "..." > output.txt` and only get the
    /// model reply.
    static func writeStderr(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }

    /// POSIX-termios echo suppression around `readLine()`. If stdin
    /// isn't a TTY (piped / scripted setup) we fall back to a plain
    /// `readLine()` — the key won't be hidden in that case, but it lets
    /// `echo "sk-..." | aurora auth set anthropic` work for
    /// non-interactive automation.
    ///
    /// Returns `nil` on EOF (e.g., user pressed Ctrl-D before typing
    /// anything).
    static func readPasswordSilently() -> String? {
        let fd = fileno(stdin)
        guard isatty(fd) != 0 else { return readLine() }

        var oldTermios = termios()
        guard tcgetattr(fd, &oldTermios) == 0 else { return readLine() }

        var newTermios = oldTermios
        newTermios.c_lflag &= ~tcflag_t(ECHO)
        guard tcsetattr(fd, TCSAFLUSH, &newTermios) == 0 else { return readLine() }

        let line = readLine()

        // Restore previous terminal state. Print a newline so the
        // cursor moves off the prompt line (the user's Enter was
        // consumed silently).
        _ = tcsetattr(fd, TCSAFLUSH, &oldTermios)
        writeStderr("\n")

        return line
    }
}
