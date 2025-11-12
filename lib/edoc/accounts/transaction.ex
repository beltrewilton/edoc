defmodule Edoc.Transactions.Transaction do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "transactions" do
    field :amount, :decimal
    field :description, :string
    field :status, :string
    field :occurred_at, :utc_datetime

    belongs_to :company, Edoc.Accounts.Company

    timestamps(type: :utc_datetime)
  end
end
