defmodule Edoc.Repo.Migrations.AddProviderFieldsToCompany do
  use Ecto.Migration

  def change do
    alter table(:company) do
      add :provider_endpoint, :string
      add :provider_apikey, :text
    end
  end
end
