#!/usr/bin/env bash
# Runs a command with the App Store Connect API key settings in its environment.
# ASC_* variables already in the environment win; anything missing is read from
# .env.local (or the file named by ASC_ENV_FILE). Only ASC_* lines are read, and
# nothing is printed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ASC_ENV_FILE:-$ROOT/.env.local}"

if [ -f "$ENV_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#export }"
    case "$line" in
      ASC_*=*) ;;
      *) continue ;;
    esac
    key="${line%%=*}"
    value="${line#*=}"
    # Strip one pair of surrounding quotes.
    case "$value" in
      \"*\") value="${value#\"}"; value="${value%\"}" ;;
      \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    if [ -z "${!key:-}" ]; then
      export "$key=$value"
    fi
  done < "$ENV_FILE"
fi

exec "$@"
