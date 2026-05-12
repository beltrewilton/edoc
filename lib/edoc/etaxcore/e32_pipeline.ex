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
                     "tipoCambio",
                     "montoGravadoTotalOtraMoneda",
                     "montoGravado1OtraMoneda",
                     "montoGravado2OtraMoneda",
                     "montoGravado3OtraMoneda",
                     "montoExentoOtraMoneda",
                     "totalITBISOtraMoneda",
                     "totalITBIS1OtraMoneda",
                     "totalITBIS2OtraMoneda",
                     "totalITBIS3OtraMoneda",
                     "montoTotalOtraMoneda",
                     "precioUnitarioItem",
                     "montoItem"
                   ])

  @spec map(map(), Company.t(), keyword()) :: map()
  def map(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    payload
    |> E31Pipeline.map(company, opts)
    |> Map.update!("encabezado", fn encabezado ->
      encabezado
      |> update_in(["idDoc"], &Map.put(&1, "tipoeCF", 32))
      |> Map.put("totales", build_totales(payload))
      |> Map.delete("otraMoneda")
    end)
    |> maybe_put_otra_moneda(payload)
    |> Map.update!("detallesItems", &build_detalles_items(&1, payload))
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

  defp maybe_put_otra_moneda(%{"encabezado" => %{} = encabezado} = mapped_payload, payload) do
    if foreign_currency_payload?(payload) do
      Map.put(
        mapped_payload,
        "encabezado",
        Map.put(encabezado, "otraMoneda", build_otra_moneda(payload, encabezado["totales"] || %{}))
      )
    else
      mapped_payload
    end
  end

  defp build_otra_moneda(payload, totales) do
    base = tax_totals_value(payload, "base_amount_currency")
    tax = tax_totals_value(payload, "tax_amount_currency")
    total = tax_totals_value(payload, "total_amount_currency")

    %{
      "tipoMoneda" =>
        PayloadSupport.value_from_keys(payload, ["tipoMoneda", "tipo_moneda", "currency"])
        |> string_or_default("USD"),
      "tipoCambio" => exchange_rate(payload) || 1,
      "impuestosAdicionalesOtraMoneda" => []
    }
    |> maybe_put_otra_amount(
      "montoGravadoTotalOtraMoneda",
      Map.has_key?(totales, "montoGravadoTotal"),
      base
    )
    |> maybe_put_otra_amount(
      "montoGravado1OtraMoneda",
      Map.has_key?(totales, "montoGravadoI1"),
      tax_group_currency_amount(payload, 18) || tax_group_currency_amount(payload, 0) || base
    )
    |> maybe_put_otra_amount(
      "montoGravado2OtraMoneda",
      Map.has_key?(totales, "montoGravadoI2"),
      tax_group_currency_amount(payload, 16) || base
    )
    |> maybe_put_otra_amount(
      "montoGravado3OtraMoneda",
      Map.has_key?(totales, "montoGravadoI3"),
      tax_group_currency_amount(payload, 0) || zero_tax_items_currency_total(payload)
    )
    |> maybe_put_otra_amount(
      "montoExentoOtraMoneda",
      Map.has_key?(totales, "montoExento"),
      total
    )
    |> maybe_put_otra_amount(
      "totalITBISOtraMoneda",
      Map.has_key?(totales, "totalITBIS"),
      tax
    )
    |> maybe_put_otra_amount(
      "totalITBIS1OtraMoneda",
      Map.has_key?(totales, "totalITBIS1"),
      tax_group_currency_tax(payload, 18) || tax_group_currency_tax(payload, 0) || tax
    )
    |> maybe_put_otra_amount(
      "totalITBIS2OtraMoneda",
      Map.has_key?(totales, "totalITBIS2"),
      tax_group_currency_tax(payload, 16) || tax
    )
    |> maybe_put_otra_amount(
      "totalITBIS3OtraMoneda",
      Map.has_key?(totales, "totalITBIS3"),
      tax_group_currency_tax(payload, 0) || 0
    )
    |> maybe_put_otra_amount("montoTotalOtraMoneda", Map.has_key?(totales, "montoTotal"), total)
  end

  defp maybe_put_otra_amount(map, _key, false, _value), do: map
  defp maybe_put_otra_amount(map, _key, true, nil), do: map
  defp maybe_put_otra_amount(map, key, true, value), do: Map.put(map, key, value)

  defp tax_group_currency_amount(payload, rate) do
    find_tax_group_by_rate(payload, rate, &PayloadSupport.numeric(Map.get(&1, "base_amount_currency")))
  end

  defp tax_group_currency_tax(payload, rate) do
    find_tax_group_by_rate(payload, rate, &PayloadSupport.numeric(Map.get(&1, "tax_amount_currency")))
  end

  defp find_tax_group_by_rate(payload, expected_rate, callback) do
    payload
    |> tax_groups()
    |> Enum.find_value(fn group ->
      group_rate =
        group
        |> tax_group_rate()
        |> rate_to_itbis()

      if group_rate == expected_rate, do: callback.(group)
    end)
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

  defp tax_group_rate(group) do
    base = PayloadSupport.numeric(Map.get(group, "base_amount"))
    tax = PayloadSupport.numeric(Map.get(group, "tax_amount"))

    cond do
      is_nil(base) or is_nil(tax) or PayloadSupport.zero_amount?(base) -> nil
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

  defp exchange_rate(payload) do
    PayloadSupport.exchange_rate(payload)
  end

  defp foreign_currency_payload?(payload) do
    case exchange_rate(payload) do
      nil -> false
      1 -> false
      1.0 -> false
      _rate -> true
    end
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

  defp zero_tax_items_currency_total(payload) do
    payload
    |> invoice_items()
    |> Enum.filter(&zero_tax_item?/1)
    |> Enum.reduce(0, fn item, sum ->
      sum + (PayloadSupport.numeric(PayloadSupport.payload_value(item, "price_subtotal")) || 0)
    end)
  end

  defp string_or_default(value, default) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> default
      "false" -> default
      text -> text
    end
  end

  defp add_amount(map, key, amount), do: Map.update(map, key, amount, &(&1 + amount))
end
