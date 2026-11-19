---
name: human-writing
description: Writes or revises text posted under the user's name (Jira comments, PR descriptions and replies, chat messages, email) so it reads like the user wrote it. Not for code, commit messages, or reports back to the user.
---

# Human Writing

Draft text the user will post as themselves so it sounds like a person, not a
report. Apply these rules when writing new text and when revising a draft.

## Shape

- Write 1-4 short prose paragraphs. No headings, bold, bullets, or colon
  lead-ins. Turn any list or "sentence: list" into sentences.
- Open with the point: "Thanks X," or "Looked into Y." Drop label-style openers
  such as "Following up on X:" or "Recording ... for item 2." and start with a
  plain topic sentence instead.
- End with one direct question or next step. No sign-off.

## Words

- Use first person and shared framing: "I checked the last day of runs",
  "after we flip", "did you want us to...".
- Prefer everyday verbs: "kick off", "shut off", "leave running", "still
  going", "a bit early". Replace report words with these.
- Keep hedges short and honest: "but I haven't checked".
- Avoid AI tells: "it's worth noting", "robust", lists of three, tidy
  summaries of what was just said.
- Fragments and an occasional comma splice are fine.

## Formatting

- No backticks. Drop inline code, raw IDs, config keys, commands, and citation
  parentheticals the reader will not act on.
- Spell out shorthand: "about" not "~", "2-3 hours" not an en-dash range,
  "12/31" not an ISO date, words not ALL_CAPS codes, "->" not an arrow glyph.
- No em dashes.
- Paraphrase long doc quotes in a sentence.

## Content

Keep every fact and number. Cut formality, not information.

## Process

- Show the user only the draft and "Post it?". Do not explain stylistic
  choices.
- When the user edits a draft, reuse those edits as the style for later drafts.
- A PR template keeps its section headings. Apply the voice inside each section.
