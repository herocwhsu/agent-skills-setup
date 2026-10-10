# Evaluator Rubric Example

Use 1-5 scoring for each dimension:

- Grounding: are answers clearly tied to imported sources?
  - 1: Completely ungrounded or hallucinated claims
  - 3: Partially grounded; several key assertions lack supporting source quotes
  - 5: Every single claim is strictly tied to uploaded source documents

- Citation quality: are the source references visible and specific?
  - 1: No citations or invalid references
  - 3: General document references without specific line or chunk targets
  - 5: Precise, clickable chunk and line-level citations

- Functionality: can the user complete the question-answer flow?
  - 1: Pipeline fails or unhandled crash occurs
  - 3: Flow completes but interactive citation navigation fails
  - 5: Complete end-to-end question, citation, and view jump workflow succeeds

- Product coherence: does the workflow feel integrated?
  - 1: Disjointed, fragmented UI/UX
  - 3: Functional but inconsistent styling and error presentation
  - 5: Seamless integration with existing application style and theme
