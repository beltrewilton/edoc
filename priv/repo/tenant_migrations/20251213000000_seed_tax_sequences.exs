defmodule Edoc.Repo.Migrations.SeedTaxSequences do
  use Ecto.Migration

  import Ecto.Query

  @tax_sequences [
    %{prefix: "E31", label: "E31 Factura de Crédito Fiscal Electrónica"},
    %{prefix: "E32", label: "E32 Factura de Consumo Electrónica"},
    %{prefix: "E33", label: "E33 Nota de Débito Electrónica"},
    %{prefix: "E34", label: "E34 Nota de Crédito Electrónica"},
    %{prefix: "E44", label: "E44 Comprobante Electrónico para Regímenes Especiales"},
    %{prefix: "E45", label: "E45 Comprobante Electrónico Gubernamental"},
    %{prefix: "E46", label: "E46 Comprobante Electrónico para Exportaciones"},
    %{prefix: "E41", label: "E41 Comprobante Electrónico de Compras"},
    %{prefix: "E43", label: "E43 Comprobante Electrónico para Gastos Menores"},
    %{prefix: "E47", label: "E47 Comprobante Electrónico para Pagos al Exterior"}
  ]

  def up do
    timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    tenant_prefix = prefix()

    entries =
      Enum.map(@tax_sequences, fn attrs ->
        {:ok, uuid} = Ecto.UUID.dump(Ecto.UUID.generate())

        attrs
        |> Map.put(:inserted_at, timestamp)
        |> Map.put(:id, uuid)
        |> Map.put(:updated_at, timestamp)
      end)

    repo().insert_all("tax_sequences", entries, prefix: tenant_prefix)
  end

  def down do
    prefixes = Enum.map(@tax_sequences, & &1.prefix)
    tenant_prefix = prefix()

    from(ts in "tax_sequences", where: ts.prefix in ^prefixes)
    |> repo().delete_all(prefix: tenant_prefix)
  end
end
