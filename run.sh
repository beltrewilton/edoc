#!/usr/bin/env bash

EDOC_ENV_FILE="${EDOC_ENV_FILE:-/etc/edoc/edoc.env}"
if [ -r "$EDOC_ENV_FILE" ]; then
  set -a
  . "$EDOC_ENV_FILE"
  set +a
fi

: "${SECRET_KEY_BASE:?Set SECRET_KEY_BASE in the service environment or EDOC_ENV_FILE}"
: "${DB_PASS:?Set DB_PASS in the service environment or EDOC_ENV_FILE}"
: "${GOOGLE_KEY:?Set GOOGLE_KEY in the service environment or EDOC_ENV_FILE}"
: "${GOOGLE_CLIENT:?Set GOOGLE_CLIENT in the service environment or EDOC_ENV_FILE}"
: "${ERLANG_COOKIE:?Set ERLANG_COOKIE in the service environment or EDOC_ENV_FILE}"
export SECRET_KEY_BASE DB_PASS GOOGLE_KEY GOOGLE_CLIENT ERLANG_COOKIE

export PATH=$HOME/.elixir-install/installs/otp/27.1.2/bin:$PATH
export PATH=$HOME/.elixir-install/installs/elixir/1.17.2-otp-27/bin:$PATH

. "$HOME/.cargo/env"

export PLEX_CFG=/home/wilton/plex_env/plex/plex_cfg/ccd.cfg
export WHATSAPP_ELIXIR_PATH=/home/wilton/plex_env/whatsapp_elixir
export WHATSAPP_FLOW_CRYPTO_PATH=/home/wilton/plex_env/whatsapp_flow_crypto


export DB_USER=edoc
export DB_NAME=edoc_dev

export WEBHOOK_URL=https://edoc.tigoo.app
export PORT=4001
export PHX_HOST=edoc.tigoo.app

export LOG_DIR=/home/wilton/edoc/logs



cd /home/wilton/edoc

# elixir  -S mix phx.server --no-halt
elixir --name edoc@10.132.102.216 --cookie "$ERLANG_COOKIE" -S mix phx.server --no-halt
