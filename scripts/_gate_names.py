"""Gate names as harness-verify.sh prints them, and the files the runtime-drift gate compares."""

GATES = (
    "registry",
    "types",
    "tests",
    "skill paths",
    "bash compat",
    "cred backends",
    "hook wiring",
    "state layer",
    "clean state",
    "runtime drift",
    "secret scan",
)

RUNTIME_FILES = (
    ("lib/lib.sh", "lib.sh"),
    ("scripts/credentials/_store.sh", "_store.sh"),
    ("scripts/outside-agent.sh", "outside-agent.sh"),
    ("scripts/outside_agent.py", "outside_agent.py"),
    ("templates/hooks/global/global-hook.sh", "hooks/global-hook.sh"),
    ("templates/hooks/common/agent-hook.sh", "hooks/agent-hook.sh"),
    ("templates/hooks/common/sh-check.sh", "hooks/sh-check.sh"),
    ("templates/hooks/common/secret-scan.sh", "hooks/secret-scan.sh"),
    ("templates/hooks/common/preflight.sh", "hooks/preflight.sh"),
)
