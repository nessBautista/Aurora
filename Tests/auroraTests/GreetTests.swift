import XCTest
@testable import AuroraCLI

final class GreetTests: XCTestCase {
    func testGreetReturnsHelloName() {
        XCTAssertEqual(greet(name: "world"), "Hello, world!")
    }

    func testGreetHandlesEmptyName() {
        XCTAssertEqual(greet(name: ""), "Hello, !")
    }
}
