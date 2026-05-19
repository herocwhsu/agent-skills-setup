#!/usr/bin/env bash
# credentials/jira.sh — shim, delegates to service.sh
# Kept for backward compatibility with existing references.
exec bash "$(dirname "$0")/service.sh" jira "$@"
