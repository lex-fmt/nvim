#!/usr/bin/env bash
set -euo pipefail

FORMATTER="junit"
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --format=simple) FORMATTER="pretty" ;;
        --format=junit) FORMATTER="junit" ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/bats-harness.bash"

harness_require_bats

exec bats "$SCRIPT_DIR/lex_nvim_plugin.bats" --formatter "$FORMATTER"
