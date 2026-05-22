import XCTest
@testable import AuroraModels

// MARK: - Encoding round-trips

final class EncodingTests: XCTestCase {

    func testEncodeTextBlock() {
        let dict = encodeBlock(.text("hello"))
        XCTAssertEqual(dict["type"] as? String, "text")
        XCTAssertEqual(dict["text"] as? String, "hello")
    }

    func testEncodeToolUseBlock() {
        let dict = encodeBlock(.toolUse(
            id: "tu_1",
            name: "read_file",
            input: ["path": "/tmp/foo"]
        ))
        XCTAssertEqual(dict["type"] as? String, "tool_use")
        XCTAssertEqual(dict["id"] as? String, "tu_1")
        XCTAssertEqual(dict["name"] as? String, "read_file")
        let input = try? XCTUnwrap(dict["input"] as? [String: Any])
        XCTAssertEqual(input?["path"] as? String, "/tmp/foo")
    }

    func testEncodeToolResultBlock() {
        let dict = encodeBlock(.toolResult(toolUseId: "tu_1", content: "(cancelled)"))
        XCTAssertEqual(dict["type"] as? String, "tool_result")
        XCTAssertEqual(dict["tool_use_id"] as? String, "tu_1")
        XCTAssertEqual(dict["content"] as? String, "(cancelled)")
    }

    func testEncodeMessagesShape() {
        let msgs = [
            Message(role: "user", content: [.text("hi")]),
            Message(role: "assistant", content: [.text("hello back")]),
        ]
        let encoded = encodeMessages(msgs)
        XCTAssertEqual(encoded.count, 2)
        XCTAssertEqual(encoded[0]["role"] as? String, "user")
        XCTAssertEqual(encoded[1]["role"] as? String, "assistant")
        let firstContent = encoded[0]["content"] as? [[String: Any]]
        XCTAssertEqual(firstContent?.first?["text"] as? String, "hi")
    }
}

// MARK: - Parsing

final class ParsingTests: XCTestCase {

    func testParseText() {
        let blocks = parseContentBlocks([
            ["type": "text", "text": "hello"],
        ])
        XCTAssertEqual(blocks.count, 1)
        guard case .text(let s) = blocks[0] else {
            XCTFail("expected .text"); return
        }
        XCTAssertEqual(s, "hello")
    }

    func testParseToolUse() {
        let blocks = parseContentBlocks([
            ["type": "tool_use", "id": "tu_1", "name": "echo", "input": ["msg": "hi"]],
        ])
        XCTAssertEqual(blocks.count, 1)
        guard case .toolUse(let id, let name, let input) = blocks[0] else {
            XCTFail("expected .toolUse"); return
        }
        XCTAssertEqual(id, "tu_1")
        XCTAssertEqual(name, "echo")
        XCTAssertEqual(input["msg"] as? String, "hi")
    }

    func testParseSkipsUnknownTypes() {
        // Forward-compat: future Anthropic block types we don't know about
        // are dropped silently instead of crashing the response decode.
        let blocks = parseContentBlocks([
            ["type": "text", "text": "keep"],
            ["type": "future_block", "payload": "drop me"],
        ])
        XCTAssertEqual(blocks.count, 1)
        guard case .text(let s) = blocks[0] else {
            XCTFail("expected .text"); return
        }
        XCTAssertEqual(s, "keep")
    }

    func testParseSkipsMalformedBlocks() {
        // Missing required field → drop the block, don't crash.
        let blocks = parseContentBlocks([
            ["type": "text"],                  // missing "text"
            ["type": "tool_use", "id": "x"],   // missing name + input
        ])
        XCTAssertTrue(blocks.isEmpty)
    }
}

// MARK: - extractText

final class ExtractTextTests: XCTestCase {

    func testExtractFromEmpty() {
        XCTAssertEqual(extractText([]), "")
    }

    func testExtractFromSingleText() {
        XCTAssertEqual(extractText([.text("hello")]), "hello")
    }

    func testExtractJoinsTextBlocksWithNewlines() {
        let blocks: [ContentBlock] = [.text("line1"), .text("line2")]
        XCTAssertEqual(extractText(blocks), "line1\nline2")
    }

    func testExtractIgnoresNonTextBlocks() {
        let blocks: [ContentBlock] = [
            .text("before"),
            .toolUse(id: "tu", name: "x", input: [:]),
            .text("after"),
        ]
        XCTAssertEqual(extractText(blocks), "before\nafter")
    }
}

// MARK: - MessageNormalizer.normalize

final class MessageNormalizerTests: XCTestCase {

    func testNoOpOnCleanSingleTurn() {
        // Single-turn shape — the common production case.
        // Must come back identical (well, equivalent).
        let msgs = [Message(role: "user", content: [.text("hi")])]
        let result = MessageNormalizer.normalize(msgs)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].role, "user")
        XCTAssertEqual(extractText(result[0].content), "hi")
    }

    func testInsertsPlaceholderForOrphanedToolUse() {
        // Assistant emitted a tool_use; loop was interrupted before the
        // matching tool_result was appended. Normalizer must insert a
        // "(cancelled)" placeholder so the next API call validates.
        let msgs = [
            Message(role: "user", content: [.text("ask")]),
            Message(role: "assistant", content: [
                .toolUse(id: "tu_1", name: "read_file", input: [:]),
            ]),
        ]
        let result = MessageNormalizer.normalize(msgs)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[2].role, "user")
        guard case .toolResult(let toolUseId, let content) = result[2].content[0] else {
            XCTFail("expected .toolResult"); return
        }
        XCTAssertEqual(toolUseId, "tu_1")
        XCTAssertEqual(content, "(cancelled)")
    }

    func testNoPlaceholderWhenResultAlreadyPresent() {
        // tool_use → matching tool_result already in history → no placeholder added.
        let msgs = [
            Message(role: "assistant", content: [
                .toolUse(id: "tu_1", name: "x", input: [:]),
            ]),
            Message(role: "user", content: [
                .toolResult(toolUseId: "tu_1", content: "done"),
            ]),
        ]
        let result = MessageNormalizer.normalize(msgs)
        XCTAssertEqual(result.count, 2)
    }

    func testMergesConsecutiveSameRoleMessages() {
        // Anthropic requires strict user/assistant alternation. Adjacent
        // same-role messages must be merged by concatenating their content.
        let msgs = [
            Message(role: "user", content: [.text("part 1")]),
            Message(role: "user", content: [.text("part 2")]),
            Message(role: "assistant", content: [.text("reply")]),
        ]
        let result = MessageNormalizer.normalize(msgs)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].role, "user")
        XCTAssertEqual(extractText(result[0].content), "part 1part 2")
        XCTAssertEqual(result[1].role, "assistant")
    }

    func testEmptyInputReturnsEmptyOutput() {
        XCTAssertTrue(MessageNormalizer.normalize([]).isEmpty)
    }
}
