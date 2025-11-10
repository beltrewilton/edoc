defmodule Edoc.Repo.Migrations.CreateTransactions do
  use Ecto.Migration

  def change do
    create table(:transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :amount, :decimal, precision: 12, scale: 2
      add :description, :string
      add :status, :string
      add :occurred_at, :utc_datetime

      add :company_id, references(:company,
        type: :binary_id,
        on_delete: :delete_all
      )

      timestamps(type: :utc_datetime)
    end

    create index(:transactions, [:company_id])
    create index(:transactions, [:status])
  end
end
