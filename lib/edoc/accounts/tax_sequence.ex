defmodule Edoc.Accounts.TaxSequence do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "tax_sequences" do
    field :label, :string
    field :prefix, :string
    field :suffix, :integer

    timestamps(type: :utc_datetime)
  end

  @cast_fields [:label, :prefix, :suffix]
  @required_fields [:label, :prefix]

  def changeset(sequence, attrs) do
    sequence
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> validate_number(:suffix, greater_than_or_equal_to: 0)
  end

  def suffix_changeset(sequence, suffix) when is_integer(suffix) and suffix >= 0 do
    change(sequence, suffix: suffix)
  end
end
