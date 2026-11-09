---
name: ask
description: Answer questions about the codebase without modifying any files. Explores the code as needed to ground the answer in real sources. Use when the user types "/ask" followed by a question about how something works, where something lives, or why the code is the way it is.
---

# Ask

Read-only question answering. The user asks a question; you investigate the codebase as needed and explain. **You never edit, create, or delete files.**

## Hard rules

- **Read-only.** Do not use Edit, Write, or any file-mutating tool. No code changes, no "while I'm here" fixes, no scaffolding. If the answer implies a change, *describe* it — do not make it.
- If the user asks you to change something, say that `/ask` is read-only and they can re-run the request without `/ask` to have it applied.
- Ground answers in the actual code. Don't answer architectural questions from memory — go look.

## Workflow

1. **Read the question.** The text after `/ask` is the question. If it's genuinely ambiguous (multiple valid interpretations that lead to different answers), ask one clarifying question before digging in. Otherwise proceed.
   **Done when:** you know which question you are answering.
2. **Scale exploration to the question:**
   - *Simple* (where is X, what does this function do) → targeted Grep/Glob/Read.
   - *Architectural / cross-cutting* (how does the data flow, why is this structured this way) → broad exploration; delegate fan-out searches to the Explore agent and read the key files yourself.
   **Done when:** every claim you plan to make rests on a file and line you have read, or on a gap you will name.
3. **Answer.** Adapt length to the question — concise for simple, detailed walkthrough for complex.
   - Lead with the direct answer.
   - Back claims with clickable references: `[file.ts:42](path/to/file.ts#L42)`.
   - When you rely on knowledge not in the repo (library behavior, conventions) or hit a gap, **answer anyway and state the assumption explicitly** rather than stalling.
   **Done when:** the answer leads with the direct answer and every claim carries a reference or a stated assumption.
4. **Stop.** Output the answer only. No diffs, no follow-up edits.
   **Done when:** the answer is the last output and no file was changed.

## Output shape

- **Simple question:** 1–3 sentences + the relevant reference(s).
- **Complex question:** short summary, then a structured explanation (flow, components, why) with references throughout. Use code snippets to illustrate, not to propose changes.

## Examples of in-scope questions

- "How does authentication flow through the app?"
- "Where is the order-status enum used?"
- "Why does this component re-render on every state change?"
- "What would it take to add a new export format?" → explain the path and touchpoints; do **not** implement it.
