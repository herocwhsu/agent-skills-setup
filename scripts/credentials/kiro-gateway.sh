#!/usr/bin/env bash
# credentials/kiro-gateway.sh — shim, delegates to service.sh
exec bash "$(dirname "$0")/service.sh" kiro-gateway "$@"
