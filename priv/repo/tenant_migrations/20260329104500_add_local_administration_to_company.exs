defmodule Edoc.Repo.Migrations.AddLocalAdministrationToCompany do
  use Ecto.Migration

  def change do
    alter table(:company) do
      add :local_administration, :string
    end
  end
end
