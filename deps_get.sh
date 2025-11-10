#!/usr/bin/env bash
set -e
set -a
[ -f .env ] && . .env
set +a
case "$(uname)" in
  Linux) mix deps.get ;;
  Darwin) mix deps.get ;;
esac
