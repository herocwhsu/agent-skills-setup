---
subcommand: system-setup
group: infra
slash: /infra-system-setup <subcommand>
---

# infra/system-setup — Safe Dotfiles Deployment

Deploys dotfiles from `~/Project/system-tools/dotfiles/` to `~` using
**copy, not symlink**. A timestamped backup is taken before every change.

The symlink approach in the original `system-tools/install.sh` caused issues
because a broken config in the repo immediately corrupted the live shell.
This skill isolates the repo from the live environment.

## Subcommands

| Subcommand | What it does |
|---|---|
| `dotfiles` | Copy dotfiles to `~`, backing up existing files first |
| `status` | Show which dotfiles are in sync vs out of sync with the repo |
| `revert` | Restore the most recent backup |

## Prerequisites

- `~/Project/system-tools/` exists with a `dotfiles/` directory

## dotfiles workflow

### Step 1 — Locate source

```bash
SYSTEM_TOOLS_DIR="$HOME/Project/system-tools"
DOTFILES_DIR="$SYSTEM_TOOLS_DIR/dotfiles"
BACKUP_DIR="$HOME/.agent-skills-setup/backups/system-setup/$(date +%Y%m%d-%H%M%S)"
FILES="zshrc bashrc tmux.conf gitconfig vimrc editorconfig"

[[ -d "$DOTFILES_DIR" ]] || {
    echo "ERROR: $DOTFILES_DIR not found"
    exit 1
}
```

### Step 2 — For each dotfile

For each file in `$FILES`:

1. If `~/.$file` is a symlink — remove the symlink (do not follow it)
2. If `~/.$file` is a regular file — backup to `$BACKUP_DIR/`
3. Copy `$DOTFILES_DIR/$file` to `~/.$file`

```bash
mkdir -p "$BACKUP_DIR"

for file in $FILES; do
    src="$DOTFILES_DIR/$file"
    dst="$HOME/.$file"

    [[ -f "$src" ]] || { echo "  skip: $src not found"; continue; }

    if [[ -L "$dst" ]]; then
        rm "$dst"
        echo "  removed symlink: $dst"
    elif [[ -f "$dst" ]]; then
        cp "$dst" "$BACKUP_DIR/$file"
        echo "  backed up: $dst → $BACKUP_DIR/$file"
    fi

    cp "$src" "$dst"
    echo "  copied: $src → $dst"
done

echo ""
echo "Backup saved to: $BACKUP_DIR"
echo "Run /infra-system-setup status to verify."
```

### Step 3 — Post-copy notice

Print:
```
Dotfiles deployed. Changes take effect in a new shell session.
To apply now: source ~/.zshrc   (or ~/.bashrc)
To revert:    /infra-system-setup revert
```

Do NOT automatically source the shell files — that would affect the
current agent session unpredictably.

## status workflow

For each file in `FILES`:

```bash
for file in $FILES; do
    src="$DOTFILES_DIR/$file"
    dst="$HOME/.$file"

    if [[ -L "$dst" ]]; then
        echo "  SYMLINK  ~/.$file  (run dotfiles to convert to copy)"
    elif [[ ! -f "$dst" ]]; then
        echo "  MISSING  ~/.$file"
    elif diff -q "$src" "$dst" > /dev/null 2>&1; then
        echo "  IN SYNC  ~/.$file"
    else
        echo "  DIFFERS  ~/.$file  (repo version differs from live)"
    fi
done
```

Flag any remaining symlinks as warnings — they are the root cause of
config-corruption issues and should be converted.

## revert workflow

```bash
BACKUP_BASE="$HOME/.agent-skills-setup/backups/system-setup"

# Find the most recent backup
latest=$(ls -1d "$BACKUP_BASE"/*/  2>/dev/null | sort | tail -1)

[[ -n "$latest" ]] || { echo "ERROR: no backups found in $BACKUP_BASE"; exit 1; }

echo "Restoring from: $latest"

for bf in "$latest"*; do
    file=$(basename "$bf")
    dst="$HOME/.$file"
    cp "$bf" "$dst"
    echo "  restored: $dst"
done

echo "Revert complete. Open a new shell session to apply."
```

## Important constraints

- Never create symlinks — always copy
- Never source shell files during deployment
- Never modify files outside `~` (no `/etc` changes — use `host-optimization` for that)
- If `gitconfig` contains hardcoded `email` or absolute paths for this machine,
  note them in the status output but do not modify them
