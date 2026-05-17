defmodule Edoc.Etaxcore.E32Pipeline do
  @moduledoc """
  E32 mapper for Odoo invoice payloads.
  """

  alias Edoc.Accounts.Company
  alias Edoc.Etaxcore.E31Pipeline
  alias Edoc.Etaxcore.PayloadSupport

  @currency_fields MapSet.new([
                     "montoPago",
                     "MontoExento",
                     "MontoGravadoTotal",
                     "MontoGravadoI1",
                     "MontoGravadoI2",
                     "MontoGravadoI3",
                     "TotalITBIS1",
                     "TotalITBIS2",
                     "TotalITBIS3",
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
                     "MontoGravadoTotalOtraMoneda",
                     "MontoGravado1OtraMoneda",
                     "MontoGravado2OtraMoneda",
                     "MontoGravado3OtraMoneda",
                     "TOTALITBIS1OtraMoneda",
                     "TOTALITBIS2OtraMoneda",
                     "TOTALITBIS3OtraMoneda",
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
      |> update_in(["idDoc"], &build_id_doc/1)
      |> update_in(["comprador"], &build_comprador(&1, payload))
      |> Map.put("totales", build_totales(payload))
      |> Map.delete("otraMoneda")
    end)
    |> maybe_put_otra_moneda(payload)
    |> Map.update!("detallesItems", &build_detalles_items(&1, payload))
    |> Map.delete("tipo_cambio")
    |> PayloadSupport.normalize_currency_fields(@currency_fields)
  end

  defp build_id_doc(id_doc) do
    id_doc
    |> Map.put("tipoeCF", 32)
    |> Map.put("indicadorMontoGravado", 0)
    |> Map.delete("fechaVencimientoSecuencia")
  end

  defp build_comprador(comprador, payload) do
    comprador
    |> Map.put("rncComprador", "")
    |> maybe_put_identificador_extranjero(payload)
  end

  defp maybe_put_identificador_extranjero(comprador, payload) do
    if total_amount(payload) > 250_000 do
      Map.put(comprador, "IdentificadorExtranjero", foreign_buyer_identifier(payload))
    else
      Map.delete(comprador, "IdentificadorExtranjero")
    end
  end

  defp foreign_buyer_identifier(payload) do
    payload
    |> PayloadSupport.value_from_keys([
      "IdentificadorExtranjero",
      "identificadorExtranjero",
      "identificador_extranjero",
      "foreign_buyer_identifier",
      "foreign_customer_identifier"
    ])
    |> string_or_default("FA0922323")
  end

  defp build_totales(payload) do
    if taxable_payload?(payload) do
      payload
      |> tax_group_totals(:local)
      |> Map.merge(%{
        "MontoGravadoTotal" => base_amount(payload),
        "totalITBIS" => tax_amount(payload),
        "impuestosAdicionales" => [],
        "montoTotal" => total_amount(payload)
      })
    else
      %{
        "MontoExento" => total_amount(payload),
        "impuestosAdicionales" => [],
        "montoTotal" => total_amount(payload)
      }
    end
  end

  defp taxable_payload?(payload), do: not PayloadSupport.zero_amount?(tax_amount(payload))

  defp tax_group_totals(payload, amount_kind) do
    payload
    |> tax_groups()
    |> Enum.reduce(%{}, fn group, totals ->
      base = tax_group_amount(group, amount_kind)
      tax = tax_group_tax(group, amount_kind)

      case itbis_bucket(base, tax) do
        1 ->
          totals
          |> add_amount(amount_key(amount_kind, 1), base)
          |> maybe_put_rate(amount_kind, 1, 18)
          |> add_amount(tax_key(amount_kind, 1), tax)

        2 ->
          totals
          |> add_amount(amount_key(amount_kind, 2), base)
          |> maybe_put_rate(amount_kind, 2, 16)
          |> add_amount(tax_key(amount_kind, 2), tax)

        _other ->
          totals
      end
    end)
  end

  defp tax_group_amount(group, :local),
    do: PayloadSupport.numeric(Map.get(group, "base_amount")) || 0

  defp tax_group_amount(group, :foreign),
    do: PayloadSupport.numeric(Map.get(group, "base_amount_currency")) || 0

  defp tax_group_tax(group, :local),
    do: PayloadSupport.numeric(Map.get(group, "tax_amount")) || 0

  defp tax_group_tax(group, :foreign),
    do: PayloadSupport.numeric(Map.get(group, "tax_amount_currency")) || 0

  defp amount_key(:local, 1), do: "MontoGravadoI1"
  defp amount_key(:local, 2), do: "MontoGravadoI2"
  defp amount_key(:foreign, 1), do: "MontoGravado1OtraMoneda"
  defp amount_key(:foreign, 2), do: "MontoGravado2OtraMoneda"

  defp maybe_put_rate(totals, :local, 1, rate), do: Map.put(totals, "ITBIS1", rate)
  defp maybe_put_rate(totals, :local, 2, rate), do: Map.put(totals, "ITBIS2", rate)
  defp maybe_put_rate(totals, :foreign, _bucket, _rate), do: totals

  defp tax_key(:local, 1), do: "TotalITBIS1"
  defp tax_key(:local, 2), do: "TotalITBIS2"
  defp tax_key(:foreign, 1), do: "TOTALITBIS1OtraMoneda"
  defp tax_key(:foreign, 2), do: "TOTALITBIS2OtraMoneda"

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
    total = tax_totals_value(payload, "total_amount_currency")

    %{
      "tipoMoneda" =>
        PayloadSupport.value_from_keys(payload, ["tipoMoneda", "tipo_moneda", "currency"])
        |> string_or_default("USD"),
      "tipoCambio" => exchange_rate(payload) || 1,
      "impuestosAdicionalesOtraMoneda" => []
    }
    |> maybe_put_otra_amount(
      "montoExentoOtraMoneda",
      Map.has_key?(totales, "MontoExento"),
      total
    )
    |> Map.merge(foreign_taxable_totals(payload, totales))
    |> maybe_put_otra_amount(
      "MontoGravadoTotalOtraMoneda",
      Map.has_key?(totales, "MontoGravadoTotal"),
      tax_totals_value(payload, "base_amount_currency")
    )
    |> maybe_put_otra_amount(
      "totalITBISOtraMoneda",
      Map.has_key?(totales, "totalITBIS"),
      tax_totals_value(payload, "tax_amount_currency")
    )
    |> maybe_put_otra_amount("montoTotalOtraMoneda", Map.has_key?(totales, "montoTotal"), total)
  end

  defp foreign_taxable_totals(payload, totales) do
    if Map.has_key?(totales, "MontoGravadoTotal") do
      tax_group_totals(payload, :foreign)
    else
      %{}
    end
  end

  defp maybe_put_otra_amount(map, _key, false, _value), do: map
  defp maybe_put_otra_amount(map, _key, true, nil), do: map
  defp maybe_put_otra_amount(map, key, true, value), do: Map.put(map, key, value)

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
