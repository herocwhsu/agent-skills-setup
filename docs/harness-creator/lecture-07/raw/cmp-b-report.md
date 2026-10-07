# WIP=1 Implementation Summary Report

## Activated Features
The features were strictly activated one by one according to the queue F1 -> F2 -> F3 -> F4 -> F5 under WIP=1 constraints:
1. **F1**: `put <key> <val>` and `get <key>` (stores/retrieves in store.json, exit 0 on success; exit 1 and prints 'Key not found' if key not found)
2. **F2**: `delete <key>` (removes key from store.json, exit 0 on success; exit 1 if key not found)
3. **F3**: `list --prefix <pfx>` (lists matching keys alphabetically one per line, exit 0)
4. **F4**: `export --json` (dumps full JSON store to stdout, exit 0)
5. **F5**: `stats` (prints JSON with keys 'count' and 'size_bytes', exit 0)

## Verification Results
- **F1**: Verified passing (`test_f1.py`)
- **F2**: Verified passing (`test_f2.py`)
- **F3**: Verified passing (`test_f3.py`)
- **F4**: Verified passing (`test_f4.py`)
- **F5**: Verified passing (`test_f5.py`)

All regression tests for previous features remained green upon each subsequent feature activation and verification.

## Verified Completion Rate
- **Features Activated**: 5 (F1, F2, F3, F4, F5)
- **Features Verified Passing**: 5 (F1, F2, F3, F4, F5)
- **Verified Completion Rate**: 5 / 5 (100%)
