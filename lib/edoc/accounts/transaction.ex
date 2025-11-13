defmodule Edoc.Transaction do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "transactions" do
    field :odoo_request, :map
    field :provider_request, :map
    field :provider_response, :map

    field :odoo_request_at, :utc_datetime
    field :provider_request_at, :utc_datetime
    field :provider_response_at, :utc_datetime

    belongs_to :company, Edoc.Accounts.Company

    timestamps(type: :utc_datetime)
  end
end
