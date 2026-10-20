#!/usr/bin/env bash
set -euo pipefail

readonly DEFAULT_URL="http://localhost:8080"
readonly EXPECTED_STATUS=200
readonly TIMEOUT_SECONDS=10

main() {
    local url="${1:-$DEFAULT_URL}"

    require_curl

    local status
    status="$(request_status "$url")"

    if [ -z "$status" ] || [ "$status" = "000" ]; then
        fail "no HTTP response from ${url} within ${TIMEOUT_SECONDS}s"
    fi

    if [ "$status" -ne "$EXPECTED_STATUS" ]; then
        fail "${url} returned ${status}, expected ${EXPECTED_STATUS}"
    fi

    printf 'healthcheck: OK - %s returned %s\n' "$url" "$status"
}

require_curl() {
    if ! command -v curl >/dev/null 2>&1; then
        printf 'healthcheck: ERROR - curl is required but not installed\n' >&2
        exit 2
    fi
}

request_status() {
    curl --silent --location --max-time "$TIMEOUT_SECONDS" \
        --output /dev/null --write-out '%{http_code}' "$1" || true
}

fail() {
    printf 'healthcheck: FAIL - %s\n' "$1" >&2
    exit 1
}

main "$@"
