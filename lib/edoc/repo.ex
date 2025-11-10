defmodule Edoc.Repo do
  use Ecto.Repo,
    otp_app: :edoc,
    adapter: Ecto.Adapters.Postgres
end
