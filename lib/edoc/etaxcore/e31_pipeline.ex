defmodule Edoc.Etaxcore.E31Pipeline do
  @moduledoc """
  E31 mapper for Odoo invoice payloads.
  """

  alias Edoc.Accounts.Company

  @fecha_vencimiento_secuencia "31-12-2028"
  @direccion_comprador_max_length 99
  @currency_fields MapSet.new([
                     "montoPago",
                     "montoGravadoTotal",
                     "montoGravadoI1",
                     "montoGravadoI2",
                     "montoGravadoI3",
                     "MontoExento",
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
                     "MontoExentoOtraMoneda",
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
    %{
      "encabezado" => %{
        "version" => "1.0",
        "idDoc" => build_id_doc(payload, opts),
        "emisor" => build_emisor(payload, company),
        "comprador" => build_comprador(payload),
        "informacionesAdicionales" => build_informaciones_adicionales(payload),
        "totales" => build_totales(payload)
      },
      "detallesItems" => build_detalles_items(payload),
      "subtotales" => [],
      "descuentosORecargos" => [],
      "paginacion" => [],
      "fechaHoraFirma" => build_fecha_hora_firma(payload, opts)
    }
    |> maybe_put_otra_moneda(payload)
    |> maybe_put_tipo_cambio(payload)
    |> normalize_currency_fields()
  end

  defp build_id_doc(payload, opts) do
    tipo_pago = tipo_pago(payload)

    %{
      "tipoeCF" => 31,
      "encf" => string_or_empty(Keyword.get(opts, :e_doc)),
      "fechaVencimientoSecuencia" => @fecha_vencimiento_secuencia,
      "indicadorMontoGravado" => indicador_monto_gravado(payload),
      "tipoIngresos" => "01",
      "tipoPago" => tipo_pago,
      "tablaFormasPago" => [
        %{
          "formaPago" => 2,
          "montoPago" => total_amount(payload)
        }
      ]
    }
    |> maybe_put_fecha_limite_pago(payload, tipo_pago)
  end

  defp maybe_put_fecha_limite_pago(id_doc, payload, 2) do
    explicit =
      payload
      |> value_from_keys(["FechaLimitePago", "fechaLimitePago", "fecha_limite_pago"])
      |> format_date()

    fecha_limite =
      if explicit == "" do
        payload
        |> payload_value("invoice_date")
        |> add_days_to_date(13)
        |> format_date()
      else
        explicit
      end

    if fecha_limite == "", do: id_doc, else: Map.put(id_doc, "FechaLimitePago", fecha_limite)
  end

  defp maybe_put_fecha_limite_pago(id_doc, _payload, _tipo_pago), do: id_doc

  defp build_emisor(payload, %Company{} = company) do
    %{
      "rncEmisor" => rnc_or_empty(company_field(company, :rnc)),
      "razonSocialEmisor" => string_or_empty(company_field(company, :company_name)),
      "nombreComercial" => string_or_empty(company_field(company, :company_name)),
      "direccionEmisor" => value_or_default(company_address(company), "N/A"),
      "tablaTelefonoEmisor" => company_phone_list(company),
      "correoEmisor" => string_or_empty(company_email(company)),
      "webSite" => string_or_empty(company_website(company)),
      "codigoVendedor" => string_or_empty(company_field(company, :codigo_vendedor)),
      "numeroFacturaInterna" => string_or_empty(payload_value(payload, "payment_reference")),
      "zonaVenta" => string_or_empty(payload_value(payload, "zona_venta")),
      "fechaEmision" => format_date(payload_value(payload, "invoice_date"))
    }
  end

  defp build_comprador(payload) do
    %{
      "rncComprador" => rnc_or_empty(customer_tax_id(payload)),
      "razonSocialComprador" => string_or_empty(customer_name(payload)),
      "contactoComprador" =>
        string_or_empty(payload_value(payload, "contacto_comprador") || customer_name(payload)),
      "tablaTelefonoComprador" => buyer_phone_list(payload),
      "correoComprador" =>
        string_or_empty(
          payload_value(payload, "partner_email") ||
            payload_value(payload, "correo_comprador") || payload_value(payload, "email")
        ),
      "direccionComprador" =>
        direccion_comprador(
          payload_value(payload, "direccionComprador") ||
            payload_value(payload, "partner_address") ||
            payload_value(payload, "direccion_comprador")
        ),
      "municipioComprador" => string_or_empty(payload_value(payload, "municipio_comprador")),
      "provinciaComprador" => string_or_empty(payload_value(payload, "provincia_comprador")),
      "fechaEntrega" => format_date(payload_value(payload, "invoice_date_due")),
      "fechaOrdenCompra" => format_date(payload_value(payload, "invoice_date")),
      "numeroOrdenCompra" =>
        string_or_empty(
          payload_value(payload, "invoice_origin") ||
            payload_value(payload, "payment_reference") || payload_value(payload, "name")
        ),
      "codigoInternoComprador" =>
        string_or_empty(
          payload_value(payload, "commercial_partner_id") || payload_value(payload, "partner_id")
        )
    }
  end

  defp build_informaciones_adicionales(payload) do
    %{
      "numeroContenedor" => string_or_empty(payload_value(payload, "numero_contenedor")),
      "numeroReferencia" => payload_value(payload, "_id") || payload_value(payload, "id") || ""
    }
  end

  defp build_totales(payload) do
    cond do
      foreign_currency_payload?(payload) and zero_amount?(tax_amount(payload)) ->
        %{
          "MontoExento" => total_amount(payload),
          "totalITBIS" => 0,
          "impuestosAdicionales" => [],
          "montoTotal" => total_amount(payload)
        }

      true ->
        payload
        |> taxable_totals()
        |> Map.merge(%{
          "montoGravadoTotal" => base_amount(payload),
          "totalITBIS" => tax_amount(payload),
          "impuestosAdicionales" => [],
          "montoTotal" => total_amount(payload)
        })
    end
  end

  defp taxable_totals(payload) do
    totals_from_tax_groups(payload)
    |> maybe_put_zero_tax_items(payload)
  end

  defp totals_from_tax_groups(payload) do
    payload
    |> tax_groups()
    |> Enum.reduce(%{}, fn group, totals ->
      base = numeric(Map.get(group, "base_amount")) || 0
      tax = numeric(Map.get(group, "tax_amount")) || 0

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

        3 ->
          totals
          |> add_amount("montoGravadoI3", base)
          |> Map.put("itbis3", 0)
          |> add_amount("totalITBIS3", tax)

        _ ->
          totals
      end
    end)
  end

  defp maybe_put_zero_tax_items(totals, payload) do
    zero_tax_total =
      payload
      |> invoice_items()
      |> Enum.filter(&zero_tax_item?/1)
      |> Enum.reduce(0, fn item, sum -> sum + item_company_subtotal(item, payload) end)

    if zero_amount?(zero_tax_total) do
      totals
    else
      totals
      |> add_amount("montoGravadoI3", zero_tax_total)
      |> Map.put("itbis3", 0)
      |> add_amount("totalITBIS3", 0)
    end
  end

  defp build_detalles_items(payload) do
    payload
    |> invoice_items()
    |> Enum.with_index(1)
    |> Enum.map(fn {item, index} ->
      amount = item_company_subtotal(item, payload)
      quantity = item_quantity(item)
      unit_price = item_unit_price(item, amount, quantity, payload)

      %{
        "numeroLinea" => index,
        "tablaCodigosItem" => [],
        "indicadorFacturacion" => indicador_facturacion(item, payload),
        "nombreItem" => item_name(item),
        "indicadorBienoServicio" => item_bieno_servicio_indicator(item),
        "cantidadItem" => quantity,
        "unidadMedida" => "43",
        "tablaSubcantidad" => [],
        "precioUnitarioItem" => unit_price,
        "tablaSubDescuento" => [],
        "tablaSubRecargo" => [],
        "tablaImpuestoAdicional" => [],
        "montoItem" => amount
      }
    end)
  end

  defp indicador_facturacion(item, payload) do
    cond do
      foreign_currency_payload?(payload) -> 4
      zero_tax_item?(item) -> 3
      item_tax_rate(item, payload) == 18 -> 1
      item_tax_rate(item, payload) == 16 -> 2
      zero_amount?(tax_amount(payload)) -> 4
      true -> 1
    end
  end

  defp item_tax_rate(item, payload) do
    item
    |> tax_ids()
    |> Enum.find_value(fn tax_id ->
      payload
      |> tax_groups()
      |> Enum.find_value(fn group ->
        involved_tax_ids = Map.get(group, "involved_tax_ids", [])

        if tax_id in List.wrap(involved_tax_ids) do
          group
          |> tax_group_rate()
          |> rate_to_itbis()
        end
      end)
    end)
  end

  defp tax_group_rate(group) do
    base = numeric(Map.get(group, "base_amount"))
    tax = numeric(Map.get(group, "tax_amount"))

    cond do
      is_nil(base) or is_nil(tax) or zero_amount?(base) -> nil
      true -> Float.round(tax / base, 2)
    end
  end

  defp itbis_bucket(base, tax) do
    base
    |> tax_rate(tax)
    |> rate_to_itbis()
    |> case do
      18 -> 1
      16 -> 2
      0 -> 3
      _ -> nil
    end
  end

  defp tax_rate(base, tax) do
    cond do
      zero_amount?(base) -> nil
      true -> Float.round(tax / base, 2)
    end
  end

  defp rate_to_itbis(0.18), do: 18
  defp rate_to_itbis(0.16), do: 16
  defp rate_to_itbis(rate) when rate in [0, 0.0], do: 0
  defp rate_to_itbis(_rate), do: nil

  defp maybe_put_otra_moneda(%{"encabezado" => %{} = encabezado} = mapped_payload, payload) do
    if foreign_currency_payload?(payload) do
      Map.put(
        mapped_payload,
        "encabezado",
        Map.put(encabezado, "otraMoneda", build_otra_moneda(payload, encabezado["totales"]))
      )
    else
      mapped_payload
    end
  end

  defp build_otra_moneda(payload, totales) do
    base = total_currency_value(payload, "base_amount_currency")
    tax = total_currency_value(payload, "tax_amount_currency") || 0
    total = total_currency_value(payload, "total_amount_currency")

    %{
      "tipoMoneda" => value_as_string(payload, ["tipoMoneda", "tipo_moneda", "currency"], "USD"),
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
      tax_group_currency_amount(payload, 18) || base
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
      "MontoExentoOtraMoneda",
      Map.has_key?(totales, "MontoExento"),
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
      tax_group_currency_tax(payload, 18) || tax
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

  defp maybe_put_tipo_cambio(mapped_payload, payload) do
    if foreign_currency_payload?(payload) do
      Map.put(mapped_payload, "tipo_cambio", truncated_currency_number(exchange_rate(payload)))
    else
      mapped_payload
    end
  end

  defp maybe_put_otra_amount(map, _key, false, _value), do: map
  defp maybe_put_otra_amount(map, _key, true, nil), do: map
  defp maybe_put_otra_amount(map, key, true, value), do: Map.put(map, key, value)

  defp tax_group_currency_amount(payload, rate) do
    find_tax_group_by_rate(payload, rate, &numeric(Map.get(&1, "base_amount_currency")))
  end

  defp tax_group_currency_tax(payload, rate) do
    find_tax_group_by_rate(payload, rate, &numeric(Map.get(&1, "tax_amount_currency")))
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

  defp zero_tax_items_currency_total(payload) do
    payload
    |> invoice_items()
    |> Enum.filter(&zero_tax_item?/1)
    |> Enum.reduce(0, fn item, sum -> sum + item_original_subtotal(item) end)
  end

  defp item_company_subtotal(item, payload) do
    subtotal = item_original_subtotal(item)

    if original_currency_items?(payload) do
      subtotal * company_currency_factor(payload)
    else
      subtotal
    end
  end

  defp item_unit_price(item, amount, quantity, payload) do
    cond do
      original_currency_items?(payload) ->
        if zero_amount?(quantity) do
          item_original_unit_price(item) * company_currency_factor(payload)
        else
          amount / quantity
        end

      true ->
        item_original_unit_price(item)
    end
  end

  defp item_original_subtotal(item) do
    numeric(payload_value(item, "price_subtotal")) ||
      numeric(payload_value(item, "debit")) ||
      numeric(payload_value(item, "credit")) ||
      item_quantity(item) * item_original_unit_price(item)
  end

  defp item_original_unit_price(item) do
    numeric(payload_value(item, "price_unit")) ||
      derived_unit_price(numeric(payload_value(item, "price_subtotal")), item_quantity(item)) || 0
  end

  defp item_quantity(item), do: numeric(payload_value(item, "quantity")) || 0

  defp derived_unit_price(nil, _quantity), do: nil
  defp derived_unit_price(_amount, quantity) when quantity in [0, 0.0, nil], do: nil
  defp derived_unit_price(amount, quantity), do: amount / quantity

  defp original_currency_items?(payload) do
    foreign_currency_payload?(payload) and
      is_number(total_currency_value(payload, "base_amount_currency")) and
      amounts_equal?(
        invoice_items_original_subtotal(payload),
        total_currency_value(payload, "base_amount_currency")
      )
  end

  defp invoice_items_original_subtotal(payload) do
    payload
    |> invoice_items()
    |> Enum.reduce(0, fn item, sum -> sum + item_original_subtotal(item) end)
  end

  defp company_currency_factor(payload) do
    base = total_currency_value(payload, "base_amount")
    base_currency = total_currency_value(payload, "base_amount_currency")

    cond do
      is_nil(base) or is_nil(base_currency) or zero_amount?(base_currency) ->
        exchange_rate(payload) || 1

      true ->
        base / base_currency
    end
  end

  defp base_amount(payload) do
    total_currency_value(payload, "base_amount") ||
      numeric(payload_value(payload, "amount_untaxed")) ||
      max(total_amount(payload) - tax_amount(payload), 0)
  end

  defp tax_amount(payload) do
    total_currency_value(payload, "tax_amount") ||
      numeric(value_from_keys(payload, ["amount_tax", "tax_amount"])) || 0
  end

  defp total_amount(payload) do
    total_currency_value(payload, "total_amount") ||
      numeric(payload_value(payload, "amount_total")) || 0
  end

  defp total_currency_value(payload, key) do
    payload
    |> payload_value("tax_totals")
    |> case do
      %{} = totals -> numeric(Map.get(totals, key))
      _ -> nil
    end
  end

  defp tax_groups(payload) do
    payload
    |> payload_value("tax_totals")
    |> case do
      %{} = totals ->
        totals
        |> Map.get("subtotals", [])
        |> List.wrap()
        |> Enum.flat_map(fn subtotal -> subtotal |> Map.get("tax_groups", []) |> List.wrap() end)
        |> Enum.filter(&is_map/1)

      _ ->
        []
    end
  end

  defp invoice_items(payload) do
    payload
    |> payload_value("invoice_items")
    |> List.wrap()
    |> Enum.map(&normalize_item/1)
  end

  defp normalize_item(%{} = item), do: item
  defp normalize_item(_), do: %{}

  defp zero_tax_item?(item), do: tax_ids(item) == []

  defp tax_ids(item) do
    item
    |> payload_value("tax_ids")
    |> List.wrap()
    |> Enum.filter(&(is_integer(&1) or is_binary(&1)))
  end

  defp indicador_monto_gravado(payload) do
    if tax_groups(payload) == [], do: 1, else: 0
  end

  defp tipo_pago(payload) do
    payment_term_id =
      payload
      |> payload_value("invoice_payment_term_id")
      |> odoo_reference_id()

    invoice_date = payload |> payload_value("invoice_date") |> format_date()
    invoice_date_due = payload |> payload_value("invoice_date_due") |> format_date()

    if invoice_date != "" and invoice_date_due != "" do
      if invoice_date_due == invoice_date, do: 1, else: 2
    else
      if payment_term_id == 1, do: 1, else: 2
    end
  end

  defp foreign_currency_payload?(payload) do
    case exchange_rate(payload) do
      nil -> false
      1 -> false
      1.0 -> false
      _rate -> true
    end
  end

  defp exchange_rate(payload) do
    numeric(value_from_keys(payload, ["tipoCambio", "tipo_cambio", "exchange_rate"]))
  end

  defp item_bieno_servicio_indicator(item) do
    type =
      item
      |> value_from_keys(["type", "product_type", "detailed_type"])
      |> string_or_empty()
      |> String.trim()
      |> String.downcase()

    if type == "service", do: 2, else: 1
  end

  defp item_name(item) do
    (payload_value(item, "name") || tuple_label(payload_value(item, "product_id")) || "")
    |> cleanup_item_name()
  end

  defp cleanup_item_name(value) when is_binary(value) do
    value
    |> String.replace(~r/^\[[^\]]+\]\s*/, "")
    |> String.trim()
  end

  defp cleanup_item_name(value), do: value

  defp customer_name(payload) do
    payload_value(payload, "razonSocialComprador") ||
      payload_value(payload, "razon_social_comprador") ||
      payload_value(payload, "invoice_partner_display_name") ||
      tuple_label(payload_value(payload, "commercial_partner_id")) ||
      tuple_label(payload_value(payload, "partner_id"))
  end

  defp customer_tax_id(payload) do
    [
      "rncComprador",
      "rnc_comprador",
      "customer_rnc",
      "partner_vat",
      "vat",
      "tax_id"
    ]
    |> Enum.find_value(fn key ->
      payload
      |> payload_value(key)
      |> normalize_rnc()
    end)
  end

  defp direccion_comprador(value) do
    value
    |> string_or_empty()
    |> String.slice(0, @direccion_comprador_max_length)
  end

  defp buyer_phone_list(payload) do
    payload
    |> value_from_keys([
      "tablaTelefonoComprador",
      "tabla_telefono_comprador",
      "telefonoComprador",
      "telefono_comprador",
      "partner_phone",
      "phone"
    ])
    |> normalize_phone_candidates()
  end

  defp company_phone_list(company) do
    [:phone, :phone1, :phone2, :mobile, :telephone, :phones]
    |> Enum.flat_map(fn key ->
      case company_field(company, key) do
        nil ->
          []

        list when is_list(list) ->
          Enum.map(list, &string_or_empty/1)

        value when is_binary(value) ->
          value |> String.split([",", ";"], trim: true) |> Enum.map(&String.trim/1)

        other ->
          [string_or_empty(other)]
      end
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_phone_candidates(value) when is_list(value) do
    value
    |> Enum.map(&string_or_empty/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_phone_candidates(value) when is_binary(value) do
    value
    |> String.split([",", ";"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_phone_candidates(_value), do: []

  defp company_address(company) do
    company_field(company, :address) ||
      company_field(company, :direccion) ||
      company_field(company, :street) || company_field(company, :address_line)
  end

  defp company_email(company) do
    company_field(company, :email) ||
      company_field(company, :correo) || company_field(company, :correo_emisor)
  end

  defp company_website(company) do
    company_field(company, :website) ||
      company_field(company, :web) || company_field(company, :web_site)
  end

  defp build_fecha_hora_firma(payload, opts) do
    value =
      payload_value(payload, "fechaHoraFirma") ||
        payload_value(payload, "fecha_hora_firma") || Keyword.get(opts, :fecha_hora_firma) ||
        DateTime.utc_now(:second)

    format_datetime(value)
  end

  defp add_amount(map, key, amount), do: Map.update(map, key, amount, &(&1 + amount))

  defp add_days_to_date(value, days) do
    with date_text when is_binary(date_text) <- value,
         {:ok, date} <- Date.from_iso8601(String.trim(date_text)) do
      Date.add(date, days)
    else
      _ -> value
    end
  end

  defp amounts_equal?(left, right) when is_number(left) and is_number(right),
    do: abs(left - right) < 0.01

  defp amounts_equal?(_left, _right), do: false

  defp value_from_keys(payload, keys) when is_map(payload) and is_list(keys) do
    Enum.find_value(keys, &payload_value(payload, &1))
  end

  defp value_from_keys(_payload, _keys), do: nil

  defp value_as_string(payload, keys, default) when is_list(keys) do
    payload
    |> value_from_keys(keys)
    |> case do
      nil -> default
      false -> default
      value -> string_or_empty(value)
    end
  end

  defp payload_value(%{} = payload, key) when is_atom(key) do
    Map.get(payload, key) || Map.get(payload, Atom.to_string(key))
  end

  defp payload_value(%{} = payload, key) when is_binary(key), do: Map.get(payload, key)
  defp payload_value(_payload, _key), do: nil

  defp company_field(%Company{} = company, key) when is_atom(key), do: Map.get(company, key)

  defp tuple_label([_id, label]) when is_binary(label), do: label
  defp tuple_label(_value), do: nil

  defp rnc_or_empty(value) do
    case normalize_rnc(value) do
      nil -> ""
      rnc -> rnc
    end
  end

  defp normalize_rnc(nil), do: nil
  defp normalize_rnc(false), do: nil
  defp normalize_rnc(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_rnc(value) when is_float(value), do: value |> trunc() |> Integer.to_string()

  defp normalize_rnc(value) when is_binary(value) do
    digits = Regex.replace(~r/\D/, String.trim(value), "")
    if digits == "", do: nil, else: digits
  end

  defp normalize_rnc(value), do: value |> to_string() |> normalize_rnc()

  defp odoo_reference_id([id | _]) when is_integer(id), do: id
  defp odoo_reference_id(id) when is_integer(id), do: id

  defp odoo_reference_id(id) when is_binary(id) do
    case Integer.parse(String.trim(id)) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp odoo_reference_id(_id), do: nil

  defp numeric(nil), do: nil
  defp numeric(value) when is_integer(value) or is_float(value), do: value
  defp numeric(%Decimal{} = value), do: Decimal.to_float(value)

  defp numeric(value) when is_binary(value) do
    trimmed = String.trim(value)

    case Integer.parse(trimmed) do
      {int, ""} ->
        int

      _ ->
        case Float.parse(trimmed) do
          {float, ""} -> float
          _ -> nil
        end
    end
  end

  defp numeric(_value), do: nil

  defp zero_amount?(value) when value in [0, 0.0], do: true
  defp zero_amount?(value) when is_number(value), do: abs(value) < 0.000001
  defp zero_amount?(_value), do: false

  defp value_or_default(value, default) do
    case string_or_empty(value) do
      "" -> default
      present -> present
    end
  end

  defp string_or_empty(nil), do: ""
  defp string_or_empty(false), do: ""
  defp string_or_empty(value) when is_binary(value), do: String.trim(value)
  defp string_or_empty(value), do: to_string(value)

  defp format_date(nil), do: ""

  defp format_date(%Date{} = date) do
    Calendar.strftime(date, "%d-%m-%Y")
  end

  defp format_date(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_date()
    |> format_date()
  end

  defp format_date(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        ""

      match?({:ok, _}, Date.from_iso8601(value)) ->
        {:ok, date} = Date.from_iso8601(value)
        format_date(date)

      match?({:ok, _, _}, DateTime.from_iso8601(value)) ->
        {:ok, datetime, _offset} = DateTime.from_iso8601(value)
        format_date(datetime)

      true ->
        value
    end
  end

  defp format_date(value), do: value

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%d-%m-%Y %H:%M:%S")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%d-%m-%Y %H:%M:%S")

  defp format_datetime(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        ""

      match?({:ok, _, _}, DateTime.from_iso8601(value)) ->
        {:ok, datetime, _offset} = DateTime.from_iso8601(value)
        format_datetime(datetime)

      match?({:ok, _}, NaiveDateTime.from_iso8601(value)) ->
        {:ok, datetime} = NaiveDateTime.from_iso8601(value)
        format_datetime(datetime)

      true ->
        value
    end
  end

  defp format_datetime(_value), do: ""

  defp normalize_currency_fields(%{} = payload) do
    Map.new(payload, fn {key, value} ->
      normalized_value =
        if currency_field?(key) do
          format_currency(value)
        else
          normalize_currency_fields(value)
        end

      {key, normalized_value}
    end)
  end

  defp normalize_currency_fields(value) when is_list(value),
    do: Enum.map(value, &normalize_currency_fields/1)

  defp normalize_currency_fields(value), do: value

  defp currency_field?(key) when is_binary(key), do: MapSet.member?(@currency_fields, key)
  defp currency_field?(_key), do: false

  defp format_currency(value) do
    case Decimal.cast(value) do
      {:ok, decimal} ->
        decimal
        |> Decimal.round(2, :down)
        |> Decimal.to_string(:normal)
        |> pad_currency_decimals()

      :error ->
        value
    end
  end

  defp truncated_currency_number(nil), do: nil

  defp truncated_currency_number(value) do
    value
    |> format_currency()
    |> numeric()
  end

  defp pad_currency_decimals(value) do
    case String.split(value, ".", parts: 2) do
      [whole, fraction] ->
        "#{whole}.#{String.pad_trailing(String.slice(fraction, 0, 2), 2, "0")}"

      [whole] ->
        "#{whole}.00"
    end
  end
end
