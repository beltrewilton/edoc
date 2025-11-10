defmodule Edoc.Accounts.Company do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "company" do
    field :rnc, :string
    field :company_name, :string
    field :access_token, :string
    field :active, :boolean, default: true
    field :connected, :boolean, default: false
    field :odoo_url, :string
    field :odoo_db, :string
    field :odoo_user, :string
    field :odoo_apikey, :string

    many_to_many :users, Edoc.Accounts.User,
      join_through: "users_companies",
      join_keys: [company_id: :id, user_id: :id],
      on_replace: :delete

    has_many :transactions, Edoc.Transactions.Transaction

    timestamps(type: :utc_datetime)
  end
end
