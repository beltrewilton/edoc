defmodule Edoc.Etaxcore.E41E47Pipeline do
  @moduledoc false

  alias Edoc.Accounts.Company
  alias Edoc.Etaxcore.PayloadSupport

  @fecha_vencimiento_secuencia "31-12-2028"
  @default_currency "USD"
  @fecha_limite_pago_offsets %{41 => 7, 47 => 8}
  @currency_fields MapSet.new([
                     "montoPago",
                     "montoExento",
                     "montoTotal",
                     "totalISRRetencion",
                     "TotalITBISRetenido",
                     "tipoCambio",
                     "montoExentoOtraMoneda",
                     "montoTotalOtraMoneda",
                     "subTotalExento",
                     "montoSubTotal",
                     "montoISRRetenido",
                     "precioUnitarioItem",
                     "montoItem",
                     "precioOtraMoneda",
                     "montoItemOtraMoneda"
                   ])

  @spec map(map(), Company.t(), 41 | 47, keyword()) :: map()
  def map(payload, %Company{} = company, tipo_ecf, opts)
      when is_map(payload) and tipo_ecf in [41, 47] do
    %{
      "encabezado" => %{
        "version" => "1.0",
        "idDoc" => build_id_doc(payload, tipo_ecf, opts),
        "emisor" => build_emisor(payload, company),
        "comprador" => build_comprador(payload, company, tipo_ecf),
        "totales" => build_totales(payload, tipo_ecf, retention_amount(payload, tipo_ecf))
      },
      "detallesItems" => build_detalles_items(payload, tipo_ecf, retention_amount(payload, tipo_ecf)),
      "subtotales" => build_subtotales(payload),
      "descuentosORecargos" => [],
      "paginacion" => [],
      "fechaHoraFirma" => build_fecha_hora_firma(payload, opts)
    }
    |> maybe_put_otra_moneda(payload, tipo_ecf)
    |> PayloadSupport.normalize_currency_fields(@currency_fields)
  end

  defp build_id_doc(payload, tipo_ecf, opts) do
    %{
      "tipoeCF" => tipo_ecf,
      "encf" => string_or_empty(Keyword.get(opts, :e_doc)),
      "fechaVencimientoSecuencia" => @fecha_vencimiento_secuencia,
      "tablaFormasPago" => [],
      "FechaLimitePago" => fecha_limite_pago(payload, tipo_ecf),
      "numeroCuentaPago" =>
        value_as_string(payload, ["numeroCuentaPago", "numero_cuenta_pago"], ""),
      "bancoPago" => value_as_string(payload, ["bancoPago", "banco_pago"], "")
    }
    |> maybe_put_e41_id_doc_fields(payload, tipo_ecf)
  end

  defp maybe_put_e41_id_doc_fields(id_doc, payload, 41) do
    id_doc
    |> Map.put("indicadorMontoGravado", 1)
    |> Map.put("tipoPago", PayloadSupport.numeric(PayloadSupport.payload_value(payload, "tipoPago")) || 2)
  end

  defp maybe_put_e41_id_doc_fields(id_doc, _payload, _tipo_ecf), do: id_doc

  defp build_emisor(payload, %Company{} = company) do
    %{
      "rncEmisor" => rnc_or_empty(company_field(company, :rnc)),
      "razonSocialEmisor" => string_or_empty(company_field(company, :company_name)),
      "nombreComercial" => string_or_empty(company_field(company, :company_name)),
      "direccionEmisor" => value_or_default(company_address(company), "N/A"),
      "tablaTelefonoEmisor" => company_phone_list(company),
      "correoEmisor" => string_or_empty(company_email(company)),
      "webSite" => string_or_empty(company_website(company)),
      "numeroFacturaInterna" =>
        string_or_empty(PayloadSupport.payload_value(payload, "payment_reference")),
      "numeroPedidoInterno" => internal_order_number(payload),
      "fechaEmision" => format_date(PayloadSupport.payload_value(payload, "invoice_date"))
    }
  end

  defp build_comprador(payload, %Company{} = company, 47) do
    supplier_comprador(payload, company)
  end

  defp build_comprador(payload, %Company{} = _company, 41) do
    %{
      "rncComprador" =>
        payload
        |> PayloadSupport.value_from_keys([
          "rncComprador",
          "rnc_comprador",
          "rncEmisor",
          "rnc_emisor",
          "partner_vat",
          "vat"
        ])
        |> normalize_vat()
        |> string_or_empty(),
      "razonSocialComprador" =>
        string_or_empty(
          PayloadSupport.value_from_keys(payload, [
            "razonSocialComprador",
            "razon_social_comprador",
            "razonSocialEmisor",
            "razon_social_emisor"
          ]) || customer_name(payload)
        )
    }
  end

  defp supplier_comprador(payload, %Company{} = _company) do
    %{
      "identificadorExtranjero" => foreign_buyer_identifier(payload),
      "razonSocialComprador" =>
        string_or_empty(
          PayloadSupport.value_from_keys(payload, [
            "razonSocialComprador",
            "razon_social_comprador",
            "razonSocialEmisor",
            "razon_social_emisor"
          ]) || customer_name(payload)
        )
    }
  end

  defp build_totales(payload, 41, retention) do
    monto_total = amount_exempt(payload)

    %{
      "montoExento" => monto_total,
      "impuestosAdicionales" => [],
      "montoTotal" => monto_total,
      "totalISRRetencion" => retention,
      "TotalITBISRetenido" => itbis_retention_amount(payload)
    }
  end

  defp build_totales(payload, _tipo_ecf, retention) do
    monto_total = amount_total(payload)

    %{
      "montoExento" => monto_total,
      "impuestosAdicionales" => [],
      "montoTotal" => monto_total,
      "totalISRRetencion" => retention
    }
  end

  defp build_detalles_items(payload, tipo_ecf, retention) do
    payload
    |> invoice_items(tipo_ecf)
    |> Enum.with_index(1)
    |> Enum.map(fn {item, index} ->
      quantity = item_quantity(item)
      amount = item_amount(item, quantity)
      unit_price = item_unit_price(item, quantity, amount)

      item_retention =
        positive_number(
          PayloadSupport.value_from_keys(item, ["montoISRRetenido", "monto_isr_retenido"])
        )

      foreign_amount = item_foreign_amount(item, quantity)
      foreign_unit_price = item_foreign_unit_price(item, quantity, foreign_amount)

      %{
        "numeroLinea" => index,
        "tablaCodigosItem" => [],
        "indicadorFacturacion" => indicador_facturacion(item, payload),
        "retencion" => %{
          "indicadorAgenteRetencionoPercepcion" => 1,
          "montoISRRetenido" => item_retention || retention
        },
        "nombreItem" => item_name(item),
        "indicadorBienoServicio" => 2,
        "cantidadItem" => quantity,
        "unidadMedida" => "43",
        "tablaSubcantidad" => [],
        "precioUnitarioItem" => unit_price,
        "tablaSubDescuento" => [],
        "tablaSubRecargo" => [],
        "tablaImpuestoAdicional" => [],
        "otraMonedaDetalle" => %{
          "precioOtraMoneda" => foreign_unit_price,
          "montoItemOtraMoneda" => foreign_amount
        },
        "montoItem" => amount
      }
    end)
  end

  defp indicador_facturacion(item, payload) do
    PayloadSupport.indicador_facturacion_from_tax_rate(item, payload) || 4
  end

  defp build_subtotales(payload) do
    provided =
      payload
      |> PayloadSupport.value_from_keys(["subtotales", "sub_totales"])
      |> list_or_empty()

    if provided == [] do
      [
        %{
          "numeroSubTotal" => 1,
          "descripcionSubtotal" => "N/A",
          "orden" => 1,
          "subTotalExento" => amount_total(payload),
          "montoSubTotal" => amount_total(payload),
          "lineas" => max(length(invoice_items(payload)), 1)
        }
      ]
    else
      Enum.map(provided, fn subtotal ->
        %{
          "numeroSubTotal" =>
            PayloadSupport.numeric(PayloadSupport.payload_value(subtotal, "numeroSubTotal")) || 0,
          "descripcionSubtotal" =>
            value_as_string(subtotal, ["descripcionSubtotal", "descripcion_subtotal"], ""),
          "orden" => PayloadSupport.numeric(PayloadSupport.payload_value(subtotal, "orden")) || 0,
          "subTotalExento" =>
            PayloadSupport.numeric(
              PayloadSupport.value_from_keys(subtotal, ["subTotalExento", "sub_total_exento"])
            ) || 0,
          "montoSubTotal" =>
            PayloadSupport.numeric(
              PayloadSupport.value_from_keys(subtotal, ["montoSubTotal", "monto_sub_total"])
            ) || 0,
          "lineas" =>
            PayloadSupport.numeric(PayloadSupport.payload_value(subtotal, "lineas")) || 0
        }
      end)
    end
  end

  defp maybe_put_otra_moneda(
         %{"encabezado" => %{} = encabezado} = mapped_payload,
         payload,
         tipo_ecf
       ) do
    if foreign_currency_payload?(payload) do
      Map.put(
        mapped_payload,
        "encabezado",
        Map.put(
          encabezado,
          "otraMoneda",
          build_otra_moneda(payload, encabezado["totales"] || %{}, tipo_ecf)
        )
      )
    else
      mapped_payload
    end
  end

  defp build_otra_moneda(payload, totales, tipo_ecf) do
    exempt_amount_currency = otra_moneda_exempt_amount(payload, tipo_ecf)

    %{
      "tipoMoneda" =>
        value_as_string(payload, ["tipoMoneda", "tipo_moneda", "currency"], @default_currency),
      "tipoCambio" => exchange_rate(payload) || 1,
      "impuestosAdicionalesOtraMoneda" =>
        list_or_empty(
          PayloadSupport.value_from_keys(payload, [
            "impuestosAdicionalesOtraMoneda",
            "impuestos_adicionales_otra_moneda"
          ])
        )
    }
    |> maybe_put_otra_amount(
      "montoExentoOtraMoneda",
      Map.has_key?(totales, "montoExento"),
      explicit_otra_amount(payload, ["montoExentoOtraMoneda", "monto_exento_otra_moneda"]) ||
        exempt_amount_currency
    )
    |> maybe_put_otra_amount(
      "montoTotalOtraMoneda",
      Map.has_key?(totales, "montoTotal"),
      explicit_otra_amount(payload, ["montoTotalOtraMoneda", "monto_total_otra_moneda"]) ||
        exempt_amount_currency
    )
  end

  defp otra_moneda_exempt_amount(payload, 41) do
    tax_totals_value(payload, "base_amount_currency") ||
      tax_totals_value(payload, "total_amount_currency")
  end

  defp otra_moneda_exempt_amount(payload, _tipo_ecf) do
    tax_totals_value(payload, "total_amount_currency")
  end

  defp maybe_put_otra_amount(map, _key, false, _value), do: map
  defp maybe_put_otra_amount(map, _key, true, nil), do: map
  defp maybe_put_otra_amount(map, key, true, value), do: Map.put(map, key, value)

  defp explicit_otra_amount(payload, keys),
    do: PayloadSupport.numeric(PayloadSupport.value_from_keys(payload, keys))

  defp retention_amount(payload, 41),
    do:
      positive_number(tax_totals_value(payload, "tax_amount")) ||
        positive_number(PayloadSupport.value_from_keys(payload, ["tax_amount", "amount_tax"])) ||
        positive_number(
          PayloadSupport.value_from_keys(payload, ["totalISRRetencion", "total_isr_retencion"])
        ) || 0

  defp retention_amount(payload, 47),
    do:
      positive_number(tax_totals_value(payload, "tax_amount")) ||
        positive_number(PayloadSupport.value_from_keys(payload, ["tax_amount", "amount_tax"])) ||
        positive_number(
          PayloadSupport.value_from_keys(payload, ["totalISRRetencion", "total_isr_retencion"])
        ) || 0

  defp itbis_retention_amount(payload) do
    payload
    |> tax_groups()
    |> Enum.filter(fn group -> Map.get(group, "group_name") == "ITBIS" end)
    |> Enum.reduce(0, fn group, total ->
      total + abs(PayloadSupport.numeric(Map.get(group, "tax_amount")) || 0)
    end)
  end

  defp positive_number(value) do
    case PayloadSupport.numeric(value) do
      nil -> nil
      number -> abs(number)
    end
  end

  defp invoice_items(payload), do: invoice_items(payload, 47)

  defp invoice_items(payload, tipo_ecf) do
    items =
      payload
      |> PayloadSupport.payload_value("invoice_items")
      |> List.wrap()
      |> Enum.map(&normalize_item/1)

    if original_currency_items?(payload, items) do
      exchange_rate = exchange_rate(payload)
      tax_excluded_factor = tax_excluded_currency_factor(payload, tipo_ecf)

      Enum.map(items, fn item ->
        item
        |> Map.put("__exchange_rate", exchange_rate)
        |> Map.put("__tax_excluded_factor", tax_excluded_factor)
      end)
    else
      items
    end
  end

  defp normalize_item(%{} = item), do: item
  defp normalize_item(_item), do: %{}

  defp tax_excluded_currency_factor(_payload, 41), do: 1

  defp tax_excluded_currency_factor(payload, _tipo_ecf) do
    base_amount_currency = tax_totals_value(payload, "base_amount_currency")
    total_amount_currency = tax_totals_value(payload, "total_amount_currency")

    cond do
      is_nil(base_amount_currency) or PayloadSupport.zero_amount?(base_amount_currency) -> 1
      is_nil(total_amount_currency) -> 1
      true -> total_amount_currency / base_amount_currency
    end
  end

  defp original_currency_items?(payload, items) do
    cond do
      not foreign_currency_payload?(payload) ->
        false

      not is_number(tax_totals_value(payload, "base_amount_currency")) ->
        false

      true ->
        line_subtotal =
          Enum.reduce(items, 0, fn item, total ->
            total +
              (PayloadSupport.numeric(PayloadSupport.payload_value(item, "price_subtotal")) || 0)
          end)

        amounts_equal?(line_subtotal, tax_totals_value(payload, "base_amount_currency"))
    end
  end

  defp item_quantity(item),
    do: PayloadSupport.numeric(PayloadSupport.payload_value(item, "quantity")) || 0

  defp item_unit_price(item, quantity, amount) do
    if original_currency_item?(item) and not PayloadSupport.zero_amount?(quantity) do
      amount / quantity
    else
      item_unit_price_original(item)
      |> convert_item_amount(item)
    end
  end

  defp item_unit_price_original(item) do
    PayloadSupport.numeric(PayloadSupport.payload_value(item, "price_unit")) ||
      derived_unit_price(
        PayloadSupport.numeric(PayloadSupport.payload_value(item, "price_subtotal")),
        PayloadSupport.numeric(PayloadSupport.payload_value(item, "quantity"))
      ) || 0
  end

  defp item_amount(item, quantity) do
    case PayloadSupport.numeric(PayloadSupport.payload_value(item, "price_subtotal")) do
      nil ->
        PayloadSupport.numeric(PayloadSupport.payload_value(item, "debit")) ||
          PayloadSupport.numeric(PayloadSupport.payload_value(item, "credit")) ||
          quantity * item_unit_price(item, quantity, 0)

      amount ->
        convert_item_amount(amount, item)
    end
  end

  defp item_amount_original(item, quantity) do
    PayloadSupport.numeric(PayloadSupport.payload_value(item, "price_subtotal")) ||
      PayloadSupport.numeric(PayloadSupport.payload_value(item, "debit")) ||
      PayloadSupport.numeric(PayloadSupport.payload_value(item, "credit")) ||
      quantity * item_unit_price_original(item)
  end

  defp item_foreign_amount(item, quantity) do
    explicit =
      PayloadSupport.numeric(
        PayloadSupport.value_from_keys(item, ["montoItemOtraMoneda", "monto_item_otra_moneda"])
      )

    cond do
      not is_nil(explicit) ->
        explicit

      original_currency_item?(item) ->
        item_amount_original(item, quantity) *
          (PayloadSupport.numeric(Map.get(item, "__tax_excluded_factor")) || 1)

      true ->
        item_amount_original(item, quantity)
    end
  end

  defp item_foreign_unit_price(item, quantity, foreign_amount) do
    explicit =
      PayloadSupport.numeric(
        PayloadSupport.value_from_keys(item, ["precioOtraMoneda", "precio_otra_moneda"])
      )

    cond do
      not is_nil(explicit) ->
        explicit

      original_currency_item?(item) and not PayloadSupport.zero_amount?(quantity) ->
        foreign_amount / quantity

      true ->
        item_unit_price_original(item)
    end
  end

  defp original_currency_item?(item), do: Map.has_key?(item, "__exchange_rate")

  defp derived_unit_price(nil, _quantity), do: nil
  defp derived_unit_price(_amount, quantity) when quantity in [0, 0.0, nil], do: nil
  defp derived_unit_price(amount, quantity), do: amount / quantity

  defp convert_item_amount(amount, %{} = item) when is_number(amount) do
    amount = amount * (PayloadSupport.numeric(Map.get(item, "__tax_excluded_factor")) || 1)

    case Map.get(item, "__exchange_rate") do
      rate when is_integer(rate) or is_float(rate) -> amount * rate
      _other -> amount
    end
  end

  defp amount_total(payload) do
    tax_totals_value(payload, "total_amount") ||
      PayloadSupport.numeric(PayloadSupport.payload_value(payload, "amount_total")) || 0
  end

  defp amount_exempt(payload) do
    tax_totals_value(payload, "base_amount") ||
      PayloadSupport.numeric(PayloadSupport.payload_value(payload, "amount_untaxed")) ||
      amount_total(payload)
  end

  defp tax_groups(payload), do: PayloadSupport.tax_groups(payload)

  defp tax_totals_value(payload, key) do
    payload
    |> PayloadSupport.payload_value("tax_totals")
    |> case do
      %{} = totals -> PayloadSupport.numeric(Map.get(totals, key))
      _other -> nil
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
    PayloadSupport.exchange_rate(payload)
  end

  defp fecha_limite_pago(payload, tipo_ecf) do
    explicit_date =
      payload
      |> PayloadSupport.value_from_keys([
        "FechaLimitePago",
        "fechaLimitePago",
        "fecha_limite_pago"
      ])
      |> format_date()

    if explicit_date != "" do
      explicit_date
    else
      payload
      |> PayloadSupport.payload_value("invoice_date_due")
      |> add_days_to_date(Map.get(@fecha_limite_pago_offsets, tipo_ecf, 0))
      |> format_date()
    end
  end

  defp add_days_to_date(value, days) do
    with date_text when is_binary(date_text) <- value,
         {:ok, date} <- Date.from_iso8601(String.trim(date_text)) do
      Date.add(date, days)
    else
      _other -> value
    end
  end

  defp build_fecha_hora_firma(payload, opts) do
    value =
      PayloadSupport.payload_value(payload, "fechaHoraFirma") ||
        PayloadSupport.payload_value(payload, "fecha_hora_firma") ||
        Keyword.get(opts, :fecha_hora_firma) ||
        DateTime.utc_now(:second)

    format_datetime(value)
  end

  defp internal_order_number(payload) do
    payload
    |> PayloadSupport.value_from_keys([
      "numeroPedidoInterno",
      "numero_pedido_interno",
      "invoice_origin",
      "payment_reference",
      "name"
    ])
    |> string_or_empty()
    |> String.replace(~r/\D/, "")
  end

  defp foreign_buyer_identifier(payload) do
    payload
    |> PayloadSupport.value_from_keys([
      "identificadorExtranjero",
      "identificador_extranjero",
      "rncEmisor",
      "rnc_emisor",
      "partner_vat",
      "vat",
      "rncComprador",
      "rnc_comprador",
      "commercial_partner_id",
      "partner_id"
    ])
    |> normalize_vat()
    |> string_or_empty()
  end

  defp customer_name(payload) do
    PayloadSupport.payload_value(payload, "razonSocialComprador") ||
      PayloadSupport.payload_value(payload, "razon_social_comprador") ||
      PayloadSupport.payload_value(payload, "invoice_partner_display_name") ||
      tuple_label(PayloadSupport.payload_value(payload, "commercial_partner_id")) ||
      tuple_label(PayloadSupport.payload_value(payload, "partner_id"))
  end

  defp item_name(item) do
    (PayloadSupport.payload_value(item, "name") ||
       tuple_label(PayloadSupport.payload_value(item, "product_id")) || "")
    |> strip_bracket_prefix()
  end

  defp strip_bracket_prefix(value) when is_binary(value) do
    value
    |> String.replace(~r/^\[[^\]]+\]\s*/, "")
    |> String.trim()
  end

  defp strip_bracket_prefix(value), do: value

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

  defp company_phone_list(company) do
    [:phone, :phone1, :phone2, :mobile, :telephone, :phones]
    |> Enum.flat_map(fn key ->
      case company_field(company, key) do
        nil ->
          []

        list when is_list(list) ->
          Enum.map(list, &string_or_empty/1)

        value when is_binary(value) ->
          value
          |> String.split([",", ";"], trim: true)
          |> Enum.map(&String.trim/1)

        other ->
          [string_or_empty(other)]
      end
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

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

  defp normalize_vat(nil), do: nil
  defp normalize_vat(false), do: nil
  defp normalize_vat(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_vat(value) when is_float(value), do: value |> trunc() |> Integer.to_string()

  defp normalize_vat(value) when is_binary(value) do
    digits = Regex.replace(~r/\D/, String.trim(value), "")
    if digits == "", do: nil, else: digits
  end

  defp normalize_vat(value), do: value |> to_string() |> normalize_vat()

  defp value_as_string(payload, keys, default) when is_list(keys) do
    payload
    |> PayloadSupport.value_from_keys(keys)
    |> case do
      nil -> default
      false -> default
      value -> string_or_empty(value)
    end
  end

  defp value_or_default(value, default) do
    case string_or_empty(value) do
      "" -> default
      present -> present
    end
  end

  defp list_or_empty(value) when is_list(value), do: value
  defp list_or_empty(_value), do: []

  defp company_field(%Company{} = company, key) when is_atom(key), do: Map.get(company, key)

  defp tuple_label([_id, label]) when is_binary(label), do: label
  defp tuple_label(_value), do: nil

  defp amounts_equal?(left, right) when is_number(left) and is_number(right),
    do: abs(left - right) < 0.01

  defp amounts_equal?(_left, _right), do: false

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

  defp format_date(_value), do: ""

  defp format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%d-%m-%Y %H:%M:%S")
  end

  defp format_datetime(%NaiveDateTime{} = datetime) do
    Calendar.strftime(datetime, "%d-%m-%Y %H:%M:%S")
  end

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
end
