#!/usr/bin/env bash
# credentials/gemini.sh — shim, delegates to service.sh
exec bash "$(dirname "$0")/service.sh" gemini "$@"
