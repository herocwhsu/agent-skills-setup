#!/usr/bin/env bash
# credentials/confluence.sh — shim, delegates to service.sh
# Kept for backward compatibility with existing references.
exec bash "$(dirname "$0")/service.sh" confluence "$@"
