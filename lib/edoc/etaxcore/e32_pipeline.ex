defmodule Edoc.Etaxcore.E32Pipeline do
  @moduledoc """
  E32 mapper for Odoo invoice payloads.
  """

  alias Edoc.Accounts.Company
  alias Edoc.Etaxcore.E31Pipeline
  alias Edoc.Etaxcore.PayloadSupport

  @currency_fields MapSet.new([
                     "montoPago",
                     "montoGravadoTotal",
                     "montoGravadoI1",
                     "montoGravadoI2",
                     "montoGravadoI3",
                     "montoExento",
                     "totalITBIS",
                     "totalITBIS1",
                     "totalITBIS2",
                     "totalITBIS3",
                     "montoTotal",
                     "precioUnitarioItem",
                     "montoItem"
                   ])

  @spec map(map(), Company.t(), keyword()) :: map()
  def map(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    document_payload = PayloadSupport.document_currency_payload(payload)

    document_payload
    |> E31Pipeline.map(company, opts)
    |> Map.update!("encabezado", fn encabezado ->
      encabezado
      |> update_in(["idDoc"], &Map.put(&1, "tipoeCF", 32))
      |> Map.put("totales", build_totales(document_payload))
      |> Map.delete("otraMoneda")
    end)
    |> Map.update!("detallesItems", &build_detalles_items(&1, document_payload))
    |> Map.delete("tipo_cambio")
    |> PayloadSupport.normalize_currency_fields(@currency_fields)
  end

  defp build_totales(payload) do
    cond do
      tax_groups(payload) != [] ->
        payload
        |> taxable_totals()
        |> Map.merge(%{
          "montoGravadoTotal" => base_amount(payload),
          "totalITBIS" => tax_amount(payload),
          "impuestosAdicionales" => [],
          "montoTotal" => total_amount(payload)
        })

      true ->
        %{
          "montoExento" => total_amount(payload),
          "impuestosAdicionales" => [],
          "montoTotal" => total_amount(payload)
        }
    end
  end

  defp taxable_totals(payload) do
    tax_group_totals(payload)
    |> maybe_put_zero_tax_items(payload)
  end

  defp tax_group_totals(payload) do
    payload
    |> tax_groups()
    |> Enum.reduce(%{}, fn group, totals ->
      base = PayloadSupport.numeric(Map.get(group, "base_amount")) || 0
      tax = PayloadSupport.numeric(Map.get(group, "tax_amount")) || 0

      case itbis_bucket(base, tax) do
        1 ->
          totals
          |> add_amount("montoGravadoI1", base)
          |> Map.put("itbis1", 18)
          |> add_amount("totalITBIS1", tax)

        2 ->
          totals
          |> add_amount("montoGravadoI2", base)
          |> Map.put("itbis2", 16)
          |> add_amount("totalITBIS2", tax)

        4 ->
          totals
          |> add_amount("montoGravadoI1", base)
          |> Map.put("itbis1", 0)
          |> add_amount("totalITBIS1", tax)

        _other ->
          totals
      end
    end)
  end

  defp maybe_put_zero_tax_items(totals, payload) do
    zero_tax_total =
      payload
      |> invoice_items()
      |> Enum.filter(&zero_tax_item?/1)
      |> Enum.reduce(0, fn item, sum -> sum + item_subtotal(item) end)

    cond do
      PayloadSupport.zero_amount?(zero_tax_total) ->
        totals

      tax_groups(payload) == [] ->
        totals

      true ->
        totals
        |> add_amount("montoGravadoI3", zero_tax_total)
        |> Map.put("itbis3", 0)
        |> add_amount("totalITBIS3", 0)
    end
  end

  defp build_detalles_items(items, payload) do
    items
    |> Enum.zip(invoice_items(payload))
    |> Enum.map(fn {mapped_item, source_item} ->
      Map.put(mapped_item, "indicadorFacturacion", indicador_facturacion(source_item, payload))
    end)
  end

  defp indicador_facturacion(item, payload) do
    PayloadSupport.indicador_facturacion_from_tax_rate(item, payload) || 4
  end

  defp itbis_bucket(base, tax) do
    base
    |> tax_rate(tax)
    |> rate_to_itbis()
    |> case do
      18 -> 1
      16 -> 2
      0 -> 4
      _other -> nil
    end
  end

  defp tax_rate(base, tax) do
    cond do
      PayloadSupport.zero_amount?(base) -> nil
      true -> Float.round(tax / base, 2)
    end
  end

  defp rate_to_itbis(0.18), do: 18
  defp rate_to_itbis(0.16), do: 16
  defp rate_to_itbis(rate) when rate in [0, 0.0], do: 0
  defp rate_to_itbis(_rate), do: nil

  defp base_amount(payload) do
    tax_totals_value(payload, "base_amount") ||
      PayloadSupport.numeric(PayloadSupport.payload_value(payload, "amount_untaxed")) ||
      max(total_amount(payload) - tax_amount(payload), 0)
  end

  defp tax_amount(payload) do
    tax_totals_value(payload, "tax_amount") ||
      PayloadSupport.numeric(
        PayloadSupport.value_from_keys(payload, ["amount_tax", "tax_amount"])
      ) ||
      0
  end

  defp total_amount(payload) do
    tax_totals_value(payload, "total_amount") ||
      PayloadSupport.numeric(PayloadSupport.payload_value(payload, "amount_total")) || 0
  end

  defp tax_totals_value(payload, key) do
    payload
    |> PayloadSupport.payload_value("tax_totals")
    |> case do
      %{} = totals -> PayloadSupport.numeric(Map.get(totals, key))
      _other -> nil
    end
  end

  defp tax_groups(payload) do
    PayloadSupport.tax_groups(payload)
  end

  defp invoice_items(payload) do
    payload
    |> PayloadSupport.payload_value("invoice_items")
    |> List.wrap()
    |> Enum.map(&normalize_item/1)
  end

  defp normalize_item(%{} = item), do: item
  defp normalize_item(_item), do: %{}

  defp zero_tax_item?(item), do: tax_ids(item) == []

  defp tax_ids(item) do
    PayloadSupport.item_tax_ids(item)
  end

  defp item_subtotal(item) do
    PayloadSupport.numeric(PayloadSupport.payload_value(item, "price_subtotal")) ||
      PayloadSupport.numeric(PayloadSupport.payload_value(item, "debit")) ||
      PayloadSupport.numeric(PayloadSupport.payload_value(item, "credit")) || 0
  end

  defp add_amount(map, key, amount), do: Map.update(map, key, amount, &(&1 + amount))
end
