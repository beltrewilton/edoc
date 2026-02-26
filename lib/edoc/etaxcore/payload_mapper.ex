defmodule Edoc.Etaxcore.PayloadMapper do
  @moduledoc """
  Builds the eTaxCore invoice payload from Odoo webhook data.
  """

  alias Edoc.Accounts.Company

  @spec map_invoice(map(), Company.t(), keyword()) :: map()
  def map_invoice(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    e_doc = Keyword.get(opts, :e_doc)
    doc_type = Keyword.get(opts, :doc_type)
    monto_total = amount_total(payload)

    %{
      "encabezado" => %{
        "version" => "1.0",
        "idDoc" => build_id_doc(payload, e_doc, doc_type, monto_total),
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
  end

  defp build_id_doc(payload, e_doc, doc_type, monto_total) do
    %{
      "tipoeCF" => resolve_tipo_ecf(payload, e_doc, doc_type) || 0,
      "encf" => string_or_empty(e_doc),
      "fechaVencimientoSecuencia" => format_date(payload_value(payload, "invoice_date_due")),
      "indicadorMontoGravado" => 1,
      "tipoIngresos" => "02",
      "tipoPago" => 1,
      "tablaFormasPago" => [
        %{
          "formaPago" => 1,
          "montoPago" => monto_total
        }
      ]
    }
  end

  defp build_emisor(payload, %Company{} = company) do
    %{
      "rncEmisor" => string_or_empty(company_field(company, :rnc)),
      "razonSocialEmisor" => string_or_empty(company_field(company, :company_name)),
      "nombreComercial" => string_or_empty(company_field(company, :company_name)),
      "direccionEmisor" => string_or_empty(company_address(company)),
      "municipio" => "010101",
      "provincia" => "010000",
      "tablaTelefonoEmisor" => company_phone_list(company),
      "correoEmisor" => string_or_empty(company_email(company)),
      "webSite" => string_or_empty(company_website(company)),
      "codigoVendedor" => string_or_empty(company_field(company, :codigo_vendedor)),
      "numeroFacturaInterna" => string_or_empty(payload_value(payload, "payment_reference")),
      "numeroPedidoInterno" =>
        string_or_empty(payload_value(payload, "invoice_origin") || payload_value(payload, "name")),
      "zonaVenta" => string_or_empty(company_field(company, :zona_venta)),
      "fechaEmision" => format_date(payload_value(payload, "invoice_date"))
    }
  end

  defp build_comprador(payload) do
    %{
      "rncComprador" => string_or_empty(customer_tax_id(payload)),
      "razonSocialComprador" => string_or_empty(customer_name(payload)),
      "contactoComprador" =>
        string_or_empty(payload_value(payload, "contacto_comprador") || customer_name(payload)),
      "correoComprador" =>
        string_or_empty(
          payload_value(payload, "partner_email") ||
            payload_value(payload, "correo_comprador") ||
            payload_value(payload, "email")
        ),
      "direccionComprador" =>
        string_or_empty(
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
            payload_value(payload, "payment_reference") ||
            payload_value(payload, "name")
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
    monto_gravado = amount_untaxed(payload)
    total_itbis = amount_tax(payload)

    %{
      "montoGravadoTotal" => monto_gravado,
      "montoGravadoI1" => monto_gravado,
      "itbis1" => itbis_rate(payload, monto_gravado, total_itbis),
      "totalITBIS" => total_itbis,
      "totalITBIS1" => total_itbis,
      "impuestosAdicionales" => [],
      "montoTotal" => amount_total(payload)
    }
  end

  defp build_detalles_items(payload) do
    payload
    |> payload_value("invoice_items")
    |> List.wrap()
    |> Enum.map(&normalize_item/1)
    |> Enum.with_index(1)
    |> Enum.map(fn {item, index} ->
      quantity = item_quantity(item)
      unit_price = item_unit_price(item, quantity)
      amount = item_amount(item, quantity, unit_price)

      %{
        "numeroLinea" => index,
        "tablaCodigosItem" => [],
        "indicadorFacturacion" => item_facturation_indicator(item),
        "nombreItem" => item_name(item),
        "indicadorBienoServicio" => 1,
        "cantidadItem" => quantity,
        "unidadMedida" => "31",
        "tablaSubcantidad" => [],
        "precioUnitarioItem" => unit_price,
        "tablaSubDescuento" => [],
        "tablaSubRecargo" => [],
        "tablaImpuestoAdicional" => [],
        "montoItem" => amount
      }
    end)
  end

  defp build_fecha_hora_firma(payload, opts) do
    value =
      payload_value(payload, "fechaHoraFirma") ||
        payload_value(payload, "fecha_hora_firma") ||
        Keyword.get(opts, :fecha_hora_firma) ||
        DateTime.utc_now(:second)

    format_datetime(value)
  end

  defp item_facturation_indicator(%{} = item) do
    has_taxes? =
      item
      |> payload_value("tax_ids")
      |> List.wrap()
      |> Enum.any?()

    if has_taxes?, do: 1, else: 4
  end

  defp normalize_item(%{} = item), do: item
  defp normalize_item(_), do: %{}

  defp item_name(item) do
    item =
      payload_value(item, "name") ||
        tuple_label(payload_value(item, "product_id")) ||
        ""

    item
    |> strip_bracket_prefix()
  end

  defp item_quantity(item), do: numeric(payload_value(item, "quantity")) || 1

  defp item_unit_price(item, quantity) do
    numeric(payload_value(item, "price_unit")) || derived_unit_price(item, quantity) || 0
  end

  defp item_amount(item, quantity, unit_price) do
    numeric(payload_value(item, "price_subtotal")) ||
      numeric(payload_value(item, "debit")) ||
      numeric(payload_value(item, "credit")) ||
      quantity * unit_price
  end

  defp derived_unit_price(item, quantity) when quantity in [0, 0.0], do: nil

  defp derived_unit_price(item, quantity) do
    amount =
      numeric(payload_value(item, "price_subtotal")) ||
        numeric(payload_value(item, "debit")) ||
        numeric(payload_value(item, "credit"))

    if is_number(amount), do: amount / quantity, else: nil
  end

  defp amount_total(payload) do
    numeric(payload_value(payload, "amount_total")) ||
      tax_totals_value(payload, "total_amount") ||
      0
  end

  defp amount_untaxed(payload) do
    numeric(payload_value(payload, "amount_untaxed")) ||
      tax_totals_value(payload, "base_amount") ||
      max(amount_total(payload) - amount_tax(payload), 0)
  end

  defp amount_tax(payload) do
    numeric(payload_value(payload, "amount_tax")) ||
      tax_totals_value(payload, "tax_amount") ||
      0
  end

  defp itbis_rate(payload, monto_gravado, total_itbis) do
    from_tax_totals = tax_totals_rate(payload)

    cond do
      is_integer(from_tax_totals) ->
        from_tax_totals

      zero_amount?(monto_gravado) ->
        0

      true ->
        round(total_itbis / monto_gravado * 100)
    end
  end

  defp tax_totals_rate(payload) do
    payload
    |> payload_value("tax_totals")
    |> case do
      %{} = totals ->
        totals
        |> Map.get("subtotals", [])
        |> List.wrap()
        |> Enum.find_value(fn subtotal ->
          subtotal
          |> Map.get("tax_groups", [])
          |> List.wrap()
          |> Enum.find_value(fn group ->
            base_amount = numeric(Map.get(group, "base_amount"))
            tax_amount = numeric(Map.get(group, "tax_amount"))

            cond do
              zero_amount?(base_amount) -> nil
              is_nil(base_amount) or is_nil(tax_amount) -> nil
              true -> round(tax_amount / base_amount * 100)
            end
          end)
        end)

      _ ->
        nil
    end
  end

  defp tax_totals_value(payload, key) do
    payload
    |> payload_value("tax_totals")
    |> case do
      %{} = totals -> numeric(Map.get(totals, key))
      _ -> nil
    end
  end

  defp resolve_tipo_ecf(payload, e_doc, doc_type) do
    parse_tipo_ecf(e_doc) || parse_tipo_ecf(payload_prefix(payload, doc_type))
  end

  defp payload_prefix(payload, "BILL"), do: payload_value(payload, "x_studio_e_doc_bill")
  defp payload_prefix(payload, "INV"), do: payload_value(payload, "x_studio_e_doc_inv")

  defp payload_prefix(payload, _) do
    payload_value(payload, "x_studio_e_doc_bill") || payload_value(payload, "x_studio_e_doc_inv")
  end

  defp parse_tipo_ecf(value) when is_binary(value) do
    case Regex.run(~r/^E?(\d{2})/, String.trim(value)) do
      [_, digits] -> String.to_integer(digits)
      _ -> nil
    end
  end

  defp parse_tipo_ecf(_), do: nil

  defp company_address(company) do
    company_field(company, :address) ||
      company_field(company, :direccion) ||
      company_field(company, :street) ||
      company_field(company, :address_line)
  end

  defp company_email(company) do
    company_field(company, :email) ||
      company_field(company, :correo) ||
      company_field(company, :correo_emisor)
  end

  defp company_website(company) do
    company_field(company, :website) ||
      company_field(company, :web) ||
      company_field(company, :web_site)
  end

  defp company_phone_list(company) do
    company
    |> extract_phone_candidates()
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp extract_phone_candidates(company) do
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
  end

  defp customer_name(payload) do
    payload_value(payload, "invoice_partner_display_name") ||
      tuple_label(payload_value(payload, "commercial_partner_id")) ||
      tuple_label(payload_value(payload, "partner_id"))
  end

  defp customer_tax_id(payload) do
    payload_tax_id(payload) ||
      payload
      |> payload_value("invoice_items")
      |> List.wrap()
      |> Enum.find_value(&line_tax_id/1)
  end

  defp payload_tax_id(payload) do
    [
      "rncComprador",
      "rnc_comprador",
      "customer_rnc",
      "partner_vat",
      "vat",
      "tax_id"
    ]
    |> Enum.find_value(&payload_value(payload, &1))
  end

  defp line_tax_id(%{} = line) do
    [
      "partner_vat",
      "vat",
      "rnc",
      "tax_id",
      "customer_tax_id"
    ]
    |> Enum.find_value(&payload_value(line, &1))
  end

  defp line_tax_id(_), do: nil

  defp tuple_label([_id, label]) when is_binary(label), do: label
  defp tuple_label(_), do: nil

  defp strip_bracket_prefix(value) when is_binary(value) do
    value
    |> String.replace(~r/^\[[^\]]+\]\s*/, "")
    |> String.trim()
  end

  defp strip_bracket_prefix(value), do: value

  defp company_field(%Company{} = company, key) when is_atom(key), do: Map.get(company, key)

  defp payload_value(%{} = payload, key) when is_atom(key) do
    Map.get(payload, key) || Map.get(payload, Atom.to_string(key))
  end

  defp payload_value(%{} = payload, key) when is_binary(key), do: Map.get(payload, key)
  defp payload_value(_, _), do: nil

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

  defp numeric(_), do: nil

  defp zero_amount?(value) when value in [0, 0.0], do: true
  defp zero_amount?(value) when is_number(value), do: value <= 0
  defp zero_amount?(_), do: false

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

  defp format_date(_), do: ""

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

  defp format_datetime(_), do: ""

  defp string_or_empty(nil), do: ""
  defp string_or_empty(false), do: ""
  defp string_or_empty(value) when is_binary(value), do: String.trim(value)
  defp string_or_empty(value), do: to_string(value)
end
