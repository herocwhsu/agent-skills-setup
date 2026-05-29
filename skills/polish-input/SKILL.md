---
name: polish-input
description: Use when the user wants automatic English polish on every prompt. Installs a Claude Code UserPromptSubmit hook that uses Claude Haiku 4.5 to rewrite each single-line prompt as natural English, displayed to the user as a learning side-channel. Default behavior does not change what Claude receives.
---

# polish-input

This skill installs a runtime hook for Claude Code. Once installed, every
single-line, non-slash-command prompt the user types is sent to Claude Haiku
4.5 (via the Anthropic SDK), and the polished version is printed to the
user's terminal as a learning side-channel.

See `README.md` for installation, configuration, and troubleshooting.
