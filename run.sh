#!/usr/bin/env bash

export PATH=$HOME/.elixir-install/installs/otp/27.1.2/bin:$PATH
export PATH=$HOME/.elixir-install/installs/elixir/1.17.2-otp-27/bin:$PATH

. "$HOME/.cargo/env"

export PLEX_CFG=/home/wilton/plex_env/plex/plex_cfg/ccd.cfg
export WHATSAPP_ELIXIR_PATH=/home/wilton/plex_env/whatsapp_elixir
export WHATSAPP_FLOW_CRYPTO_PATH=/home/wilton/plex_env/whatsapp_flow_crypto
export SECRET_KEY_BASE=4sEUxwlP9JWduFw6S549tA8YqjboPDVeLqwBLJHSgAE1JKmbhmqkr4Vekj3MnKHM


export DB_USER=edoc
export DB_PASS='!cUC@la10c@'
export DB_NAME=edoc_dev

export WEBHOOK_URL=https://dgii.synaia.io

export LOG_DIR=/home/wilton/edoc/logs

export GOOGLE_KEY=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
export GOOGLE_CLIENT=222025739533-fe47r6bnvinin2ntrkuntabk1qg13hp3.apps.googleusercontent.com


cd /home/wilton/edoc

# elixir  -S mix phx.server --no-halt
elixir --name edoc@10.132.102.216 --cookie wilton -S mix phx.server --no-halt