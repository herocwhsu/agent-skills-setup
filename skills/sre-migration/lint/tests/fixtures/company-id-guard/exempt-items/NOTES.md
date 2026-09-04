# Ticket notes

## `stage-target-correction.json`

**Not a real customer correction — a mechanism test file using a disposable
account on stage.** An earlier version wrongly carried the real customer's
`expected_name`/`expected_ship_to_code`, which made the guard abort on this
account. Both fields are `null` here on purpose: this file validates the
migrate/verify/rollback flow itself, not a real correction.
