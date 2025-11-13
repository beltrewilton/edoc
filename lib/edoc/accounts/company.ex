defmodule Edoc.Accounts.Company do
  use Ecto.Schema
  import Ecto.Changeset

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

    has_many :transactions, Edoc.Transaction

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating/updating a company.

  Note: Associations such as users should be set programatically with
  Ecto.Changeset.put_assoc/3 by callers (e.g. to associate the current user).
  """
  def changeset(company, attrs) do
    company
    |> cast(attrs, [
      :rnc,
      :company_name,
      :access_token,
      :active,
      :connected,
      :odoo_url,
      :odoo_db,
      :odoo_user,
      :odoo_apikey
    ])
    |> validate_required([:rnc, :company_name])
    |> validate_length(:rnc, max: 50)
    |> validate_length(:company_name, max: 160)
  end
end
