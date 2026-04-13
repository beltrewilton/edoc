defmodule Edoc.Repo.Migrations.AddEconomicActivityToCompany do
  use Ecto.Migration

  def change do
    alter table(:company) do
      add :economic_activity, :string
    end
  end
end
