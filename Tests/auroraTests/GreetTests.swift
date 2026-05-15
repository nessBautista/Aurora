import XCTest
@testable import aurora

final class GreetTests: XCTestCase {
    func testGreetReturnsHelloName() {
        XCTAssertEqual(greet(name: "world"), "Hello, world!")
    }

    func testGreetHandlesEmptyName() {
        XCTAssertEqual(greet(name: ""), "Hello, !")
    }
}
