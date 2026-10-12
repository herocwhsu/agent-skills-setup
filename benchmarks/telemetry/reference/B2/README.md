# greet

Prints a greeting.

    python3 cli.py Ana
    python3 cli.py Ana --greeting Hi
    python3 cli.py Ana --config greet.conf

## Options

- `--greeting TEXT`: the greeting word (default `Hello`).
- `--shout`: print the greeting in upper case. Also set with `shout = true` in the config file (`true` or `false`, any letter case).
- `--config PATH`: a file of `key = value` lines. Supported keys: `greeting`, `shout`.
