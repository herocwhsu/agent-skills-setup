---
name: polish-input
description: Use when the user wants automatic English polish on every prompt. Installs a Claude Code UserPromptSubmit hook that runs LanguageTool on each single-line prompt and shows the polished version on stderr. Default behavior does not change what Claude receives.
---

# polish-input

This skill installs a runtime hook for Claude Code. It does not require the agent to take action — once installed, every single-line, non-slash-command prompt the user types is run through LanguageTool, and the polished version is printed to the user's terminal as a learning side-channel.

See `README.md` for installation, configuration, and troubleshooting.
