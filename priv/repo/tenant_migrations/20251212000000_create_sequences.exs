defmodule Edoc.Repo.Migrations.CreateTaxSequences do
  use Ecto.Migration

  def change do
    create table(:tax_sequences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :label, :string
      add :prefix, :string
      add :suffix, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:tax_sequences, [:label])
    create index(:tax_sequences, [:prefix])
  end
end
