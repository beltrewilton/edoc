defmodule Edoc.Repo.Migrations.AddEdocToTransactions do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      add :edoc, :string
    end
  end
end
