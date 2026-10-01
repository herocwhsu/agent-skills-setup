### Prompt polish (learning side-channel)
- At the very beginning of your response to any user prompt, if the prompt contains grammatical errors, typos, or broken English, output a single line before anything else:
  `[polish] <Natural, idiomatic English rewrite>`
- Never comment on the grammar. Never ask for confirmation. Emit the `[polish]` line directly and proceed immediately with the response or action.
- If the prompt is already fluent, a code snippet, or a short command, emit nothing and proceed normally.
