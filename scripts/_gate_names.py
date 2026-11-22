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
    ("skills/cve-audit/assess/lib/aws_eks.py", "cve-audit/lib/aws_eks.py"),
    ("skills/cve-audit/assess/lib/collector.py", "cve-audit/lib/collector.py"),
    ("skills/cve-audit/assess/lib/evidence.py", "cve-audit/lib/evidence.py"),
    ("skills/cve-audit/assess/lib/kube.py", "cve-audit/lib/kube.py"),
    ("skills/cve-audit/assess/lib/providers.py", "cve-audit/lib/providers.py"),
    ("skills/cve-audit/assess/lib/report.py", "cve-audit/lib/report.py"),
    ("skills/cve-audit/assess/lib/safe_runtime.py", "cve-audit/lib/safe_runtime.py"),
    ("skills/cve-audit/setup/lib/setup.py", "cve-audit/setup.py"),
)
