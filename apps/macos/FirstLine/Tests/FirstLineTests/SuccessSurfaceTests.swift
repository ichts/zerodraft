import Testing
@testable import FirstLine

@MainActor
struct SuccessSurfaceTests {
    @Test
    func copyForAIPromptMatchesCanonicalString() {
        let expected =
            "Below is my raw freewriting draft. Organize it into clear notes. " +
            "Keep my original wording where possible. List any tasks or open questions separately at the end. " +
            "Do not add ideas that are not in the draft."
        #expect(SuccessText.copyForAIPrompt == expected)
    }

    @Test
    func copyForAIPayloadJoinsPromptSeparatorAndDraft() {
        let draft = "people dont lack ideas they lack permission"
        let payload = SuccessText.copyForAIPayload(for: draft)

        #expect(payload == SuccessText.copyForAIPrompt + "\n\n---\n\n" + draft)
        #expect(payload.contains("\n\n---\n\n"))
    }

    @Test
    func copyForAIPayloadTrimsSurroundingWhitespace() {
        let payload = SuccessText.copyForAIPayload(for: "\n\n  messy edges  \n")

        #expect(payload.hasSuffix("messy edges"))
        #expect(payload.contains("\n\n---\n\nmessy edges"))
    }
}
