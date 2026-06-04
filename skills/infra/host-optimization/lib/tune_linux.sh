#!/bin/bash
# Host Optimization - Linux Provider
set -euo pipefail

echo "Tuning Network parameters..."
cat <<SYSCTL | sudo tee /etc/sysctl.d/99-performance.conf
# Enable TCP BBR
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# Increase network buffer sizes for high-speed links
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216

# Swappiness optimization
vm.swappiness=10
SYSCTL

sudo sysctl --system

echo "Tuning CPU Governors..."
# Set performance governor for all available cores
if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
    echo "performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor || echo "Could not set CPU governor (might be managed by intel_pstate in active mode)"
fi

echo "Linux tuning complete."
