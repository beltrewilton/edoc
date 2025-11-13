defmodule Edoc.Transaction do
  use Ecto.Schema
  import Ecto.Changeset

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

  @cast_fields [
    :odoo_request,
    :provider_request,
    :provider_response,
    :odoo_request_at,
    :provider_request_at,
    :provider_response_at,
    :company_id
  ]

  @required_fields [:company_id, :odoo_request, :odoo_request_at]

  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> assoc_constraint(:company)
  end
end
