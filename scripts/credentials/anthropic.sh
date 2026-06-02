#!/usr/bin/env bash
# credentials/anthropic.sh — shim, delegates to service.sh
exec bash "$(dirname "$0")/service.sh" anthropic "$@"
