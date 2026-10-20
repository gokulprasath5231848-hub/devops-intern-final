#!/usr/bin/env bash
set -euo pipefail

main() {
    printf '===== System Information =====\n\n'

    printf 'User:             %s\n' "$(id -un)"
    printf 'Effective UID:    %s\n' "$(id -u)"
    printf 'Hostname:         %s\n' "$(uname -n)"
    printf 'Kernel release:   %s\n' "$(uname -r)"
    printf 'Date (ISO-8601):  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    printf '\n----- Disk usage -----\n'
    df -h

    printf '\n----- Memory usage -----\n'
    report_memory

    printf '\n----- Docker daemon -----\n'
    report_docker
}

report_memory() {
    if command -v free >/dev/null 2>&1; then
        free -h
    elif [ -r /proc/meminfo ]; then
        grep -E '^(MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo
    else
        printf 'memory: no supported source found on this host\n'
    fi
}

report_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        printf 'docker: not installed\n'
        return 0
    fi

    if docker info >/dev/null 2>&1; then
        printf 'docker: running (server %s)\n' \
            "$(docker version --format '{{.Server.Version}}')"
    else
        printf 'docker: installed but the daemon is not responding\n'
    fi
}

main "$@"
