#!/usr/bin/env bash
set -e
set -a
[ -f .env ] && . .env
set +a
case "$(uname)" in
  Linux) mix run --no-halt ;;
  Darwin) iex -S mix run ;;
esac
