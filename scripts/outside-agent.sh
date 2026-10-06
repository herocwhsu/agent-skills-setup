#!/usr/bin/env bash
# Runtime copy lives in ~/.agent-skills-setup next to outside_agent.py (install_runtime_dir).
exec python3 "$(cd "$(dirname "$0")" && pwd)/outside_agent.py" "$@"
