#!/usr/bin/env bash
# Sourced by the mock-server tests. Fixed port ranges collided with host listeners (limactl, wsagent), so ask the kernel.
free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'
}
