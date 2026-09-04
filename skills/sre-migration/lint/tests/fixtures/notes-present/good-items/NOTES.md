# Ticket notes

## What this ticket corrects

Two rows for the customer's TW account.

## Why the prod file has no expected_name

`prod-target-correction.json` sets only `expected_ship_to_code`, leaving
`expected_name` null. The account name is non-ASCII and the charset round-trip
is an untested path, so the ASCII code guards it just as effectively.
