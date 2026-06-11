import Testing
import Foundation
import MeinChatPlugin
@testable import MeinChatPlusPlugin

/// Sprint S71 §"meinchat-plus iOS" — bot conversations remain plain
/// (server-readable) so the structured `meta` field is **not** encrypted.
/// This spec pins that a plain `ChatMessage` carrying `meta` survives
/// the plus module's wire round-trip unchanged: the plus plugin imports
/// `MeinChatPlugin` and consumes the same `ChatMessage` model, so the
/// decoder must preserve `meta` end-to-end without the plus pipeline
/// dropping or mutating it.
struct PlainMetaPassThroughTests {

    @Test
    func plainBotChoicesSurvivesPlusPipelineDecode() throws {
        let json = """
        {
            "id": "m-plain-bot",
            "conversation_id": "c-bot",
            "sender_id": "shopbot",
            "protocol": "plain",
            "body": "1. Buy\\n2. Sell",
            "sent_at": "2026-06-11T10:00:00Z",
            "meta": {
                "kind": "bot_choices",
                "choices": [
                    {"label": "Buy", "action_data": "shop:buy:1"},
                    {"label": "Sell", "action_data": "shop:sell:1", "hint": "Cash out"}
                ]
            }
        }
        """
        let data = Data(json.utf8)
        let msg = try JSONDecoder().decode(ChatMessage.self, from: data)

        #expect(msg.isE2E == false,
                "Bot conversations stay plain; meta is server-readable.")
        guard case .botChoices(let choices) = msg.meta else {
            Issue.record("Expected meta to round-trip as .botChoices")
            return
        }
        #expect(choices.count == 2)
        #expect(choices[1].hint == "Cash out")
    }

    @Test
    func plainBotActionReplyDecodesUnchanged() throws {
        // Symmetric: the user's tap reply also carries plain `meta`.
        let json = """
        {
            "id": "m-plain-user",
            "protocol": "plain",
            "body": "Buy",
            "meta": {"kind": "bot_action", "action_data": "shop:buy:1"}
        }
        """
        let msg = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
        guard case .botAction(let action) = msg.meta else {
            Issue.record("Expected .botAction")
            return
        }
        #expect(action == "shop:buy:1")
        #expect(msg.isE2E == false)
    }
}
