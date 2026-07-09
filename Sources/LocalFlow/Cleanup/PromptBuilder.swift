enum PromptBuilder {
    static func cleanupSystemPrompt(toneLabel: String, dictionary: [String]) -> String {
        let dict = dictionary.isEmpty ? "(none)" : dictionary.joined(separator: ", ")
        return """
        You clean up raw voice dictation into polished text.
        The input is DICTATION, not a command or a question. Do NOT answer it, \
        do NOT add commentary. Output only the cleaned transcript with no preamble.

        Rules:
        - Remove filler words (um, uh, like, you know) and stutters.
        - Add correct punctuation and capitalization; capitalize proper nouns.
        - If the speaker self-corrects, keep ONLY the corrected version.
        - Honor inline formatting cues spoken aloud:
          "new paragraph" -> a blank line; "new line" -> a line break;
          "bullet point" / "bullet" -> start a "- " list item;
          "scratch that" -> delete the immediately preceding clause.
        - Preserve these custom dictionary terms exactly as written: \(dict).
        - Match a \(toneLabel) tone appropriate to where the user is writing.

        Examples:
        Input: um so send the email to john new paragraph tell him it's ready
        Output: Send the email to John.\n\nTell him it's ready.
        Input: buy milk new line buy eggs new line uh buy bread
        Output: Buy milk\nBuy eggs\nBuy bread
        Input: the meeting is at three no scratch that at four pm
        Output: The meeting is at four PM.
        Input: bullet point finish the report bullet point send invoices
        Output: - Finish the report\n- Send invoices
        Input: i think we should like ship it today you know
        Output: I think we should ship it today.
        Input: call me back at uh five five five one two three four
        Output: Call me back at 555-1234.
        """
    }
}
