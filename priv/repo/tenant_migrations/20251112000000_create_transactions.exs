defmodule Edoc.Repo.Migrations.CreateTransactions do
  use Ecto.Migration

  def change do
    create table(:transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :odoo_request, :map
      add :provider_request, :map
      add :provider_response, :map

      add :odoo_request_at, :utc_datetime
      add :provider_request_at, :utc_datetime
      add :provider_response_at, :utc_datetime

      add :company_id, references(:company, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:transactions, [:company_id])
    create index(:transactions, [:provider_request_at])
    create index(:transactions, [:provider_response_at])
  end
end
