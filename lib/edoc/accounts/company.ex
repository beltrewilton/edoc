defmodule Edoc.Accounts.Company do
  use Ecto.Schema
  import Ecto.Changeset

  @create_required_fields [:rnc, :company_name, :provider_endpoint, :provider_apikey]
  @onboarding_fields_by_step %{
    1 => [:rnc],
    2 => [
      :rnc,
      :company_name,
      :economic_activity,
      :local_administration,
      :odoo_url,
      :odoo_db,
      :odoo_user,
      :odoo_apikey
    ],
    3 => [
      :rnc,
      :company_name,
      :economic_activity,
      :local_administration,
      :odoo_url,
      :odoo_db,
      :odoo_user,
      :odoo_apikey,
      :provider_endpoint,
      :provider_apikey
    ]
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "company" do
    field :rnc, :string
    field :company_name, :string
    field :economic_activity, :string
    field :local_administration, :string
    field :access_token, :string
    field :provider_endpoint, :string
    field :provider_apikey, :string
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
    |> base_changeset(attrs)
    |> validate_required(@create_required_fields)
  end

  def onboarding_changeset(company, attrs, step) when is_integer(step) do
    company
    |> base_changeset(attrs)
    |> validate_required(Map.get(@onboarding_fields_by_step, step, @create_required_fields))
  end

  defp base_changeset(company, attrs) do
    company
    |> cast(attrs, [
      :rnc,
      :company_name,
      :economic_activity,
      :local_administration,
      :access_token,
      :provider_endpoint,
      :provider_apikey,
      :active,
      :connected,
      :odoo_url,
      :odoo_db,
      :odoo_user,
      :odoo_apikey
    ])
    |> validate_length(:rnc, max: 50)
    |> validate_length(:company_name, max: 160)
    |> validate_length(:economic_activity, max: 255)
    |> validate_length(:local_administration, max: 255)
    |> validate_length(:provider_endpoint, max: 255)
    |> validate_length(:provider_apikey, max: 4096)
  end
end
