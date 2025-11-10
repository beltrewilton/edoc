#!/usr/bin/env bash
set -e
set -a
[ -f .env ] && . .env
set +a
case "$(uname)" in
  Linux) mix phx.server ;;
  Darwin) iex -S mix phx.server ;;
esac
