#!/usr/bin/env bash
# Runs a command with the CloudKit server-to-server key settings in its environment.
# CK_* variables already in the environment win; anything missing is read from
# .env.local (or the file named by CK_ENV_FILE). Only CK_* lines are read, and
# nothing is printed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${CK_ENV_FILE:-$ROOT/.env.local}"

if [ -f "$ENV_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#export }"
    case "$line" in
      CK_*=*) ;;
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
