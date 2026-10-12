# greet

Prints a greeting.

    python3 cli.py Ana
    python3 cli.py Ana --greeting Hi
    python3 cli.py Ana --config greet.conf

## Options

- `--greeting TEXT`: the greeting word (default `Hello`).
- `--config PATH`: a file of `key = value` lines. Supported key: `greeting`.
