#!/usr/bin/env bash
# credentials/apidog.sh — shim, delegates to service.sh
# Kept for backward compatibility with existing references.
exec bash "$(dirname "$0")/service.sh" apidog "$@"
