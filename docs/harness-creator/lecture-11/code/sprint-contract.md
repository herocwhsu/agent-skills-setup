# Sprint Contract Example

Sprint goal:

- Add visible citations to grounded Q&A results

Done means:

- User asks a question
- App returns an answer
- At least one citation is shown
- Clicking a citation opens the source location in the document view

Scope:

- Implement citation link component
- Bind citation click event to document viewer jump target
- Unit test citation parsing and link rendering

Verification Standards:

- All unit and integration tests pass
- Manual or automated click opens the exact target citation line
- No rendering regressions on documents without citations

Exclusions:

- Not modifying document indexing backend
- Not modifying vector embedding dimension
- Not supporting third-party external URLs
