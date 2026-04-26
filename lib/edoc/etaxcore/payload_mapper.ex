defmodule Edoc.Etaxcore.PayloadMapper do
  @moduledoc """
  Pure mapping functions to transform Odoo invoice payloads into eTaxCore payloads.
  """

  alias Edoc.Accounts.Company

  # INFO: this is on QA
  @fecha_vencimiento_secuencia "31-12-2028"
  @default_e47_currency "USD"
  @default_e47_exchange_rate 60
  @fecha_limite_pago_offsets %{41 => 7, 47 => 8}
  @direccion_comprador_max_length 99
  @currency_fields MapSet.new([
                     "montoPago",
                     "montoGravadoTotal",
                     "montoGravadoI1",
                     "montoGravadoI3",
                     "totalITBIS",
                     "totalITBIS1",
                     "totalITBIS3",
                     "montoTotal",
                     "montoExento",
                     "valorPagar",
                     "totalITBISRetenido",
                     "totalISRRetencion",
                     "tipoCambio",
                     "montoExentoOtraMoneda",
                     "montoTotalOtraMoneda",
                     "valorDescuentooRecargo",
                     "montoDescuentooRecargo",
                     "subTotalExento",
                     "montoSubTotal",
                     "montoITBISRetenido",
                     "montoISRRetenido",
                     "precioUnitarioItem",
                     "montoItem",
                     "precioOtraMoneda",
                     "montoItemOtraMoneda"
                   ])

  @spec map_e31(map(), Company.t(), keyword()) :: map()
  def map_e31(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    monto_total = amount_total(payload)

    %{
      "encabezado" => %{
        "version" => "1.0",
        "idDoc" => build_id_doc_e31(payload, monto_total, 31, opts),
        "emisor" => build_emisor(payload, company),
        "comprador" => build_comprador(payload),
        "informacionesAdicionales" => build_informaciones_adicionales(payload),
        "totales" => build_totales_e31(payload)
      },
      "detallesItems" => build_detalles_items(payload),
      "subtotales" => [],
      "descuentosORecargos" => [],
      "paginacion" => [],
      "fechaHoraFirma" => build_fecha_hora_firma(payload, opts)
    }
    |> normalize_currency_fields()
  end

  @spec map_e32(map(), Company.t(), keyword()) :: map()
  def map_e32(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    monto_total = amount_total(payload)

    %{
      "encabezado" => %{
        "version" => "1.0",
        "idDoc" => build_id_doc_e31(payload, monto_total, 32, opts),
        "emisor" => build_emisor(payload, company),
        "comprador" => build_comprador(payload),
        "informacionesAdicionales" => build_informaciones_adicionales(payload),
        "totales" => build_totales_e31(payload)
      },
      "detallesItems" => build_detalles_items(payload),
      "subtotales" => [],
      "descuentosORecargos" => [],
      "paginacion" => [],
      "fechaHoraFirma" => build_fecha_hora_firma(payload, opts)
    }
    |> normalize_currency_fields()
  end

  @spec map_e33(map(), Company.t(), keyword()) :: map()
  def map_e33(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    monto_total = amount_total(payload)

    %{
      "encabezado" => %{
        "version" => "1.0",
        "idDoc" => build_id_doc_e33(payload, monto_total, opts),
        "emisor" => build_emisor(payload, company),
        "comprador" => build_comprador(payload),
        "informacionesAdicionales" => build_informaciones_adicionales(payload),
        "totales" => build_totales_e32(payload)
      },
      "detallesItems" =>
        build_detalles_items(payload, indicador_facturacion: 4, unidad_medida: "47"),
      "subtotales" => [],
      "descuentosORecargos" => [],
      "paginacion" => [],
      "informacionReferencia" => build_informacion_referencia_e33(payload),
      "fechaHoraFirma" => build_fecha_hora_firma(payload, opts)
    }
    |> normalize_currency_fields()
  end

  @spec map_e34(map(), Company.t(), keyword()) :: map()
  def map_e34(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    %{
      "encabezado" => %{
        "version" => "1.0",
        "idDoc" => build_id_doc_e34(payload, opts),
        "emisor" => build_emisor(payload, company),
        "comprador" => build_comprador(payload),
        "informacionesAdicionales" => build_informaciones_adicionales(payload),
        "totales" => build_totales_e31(payload)
      },
      "detallesItems" => build_detalles_items(payload),
      "subtotales" => [],
      "descuentosORecargos" => [],
      "paginacion" => [],
      "informacionReferencia" => build_informacion_referencia_e34(payload),
      "fechaHoraFirma" => build_fecha_hora_firma(payload, opts)
    }
    |> normalize_currency_fields()
  end

  @spec map_e41(map(), Company.t(), keyword()) :: map()
  def map_e41(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    %{
      "encabezado" => %{
        "version" => "1.0",
        "idDoc" => build_id_doc_e41(payload, opts),
        "emisor" => build_emisor_e41_from_company(payload, company),
        "comprador" => build_comprador_e41_from_supplier(payload),
        "totales" => build_totales_e41(payload)
      },
      "detallesItems" => build_detalles_items_e41(payload),
      "subtotales" => [],
      "descuentosORecargos" => [],
      "paginacion" => [],
      "fechaHoraFirma" => build_fecha_hora_firma(payload, opts)
    }
    |> normalize_currency_fields()
  end

  @spec map_e43(map(), Company.t(), keyword()) :: map()
  def map_e43(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    %{
      "encabezado" => %{
        "version" => "1.0",
        "idDoc" => build_id_doc_e43(payload, opts),
        "emisor" => build_emisor_e43_from_company(payload, company),
        "totales" => build_totales_e43(payload)
      },
      "detallesItems" =>
        build_detalles_items(payload,
          indicador_facturacion: 4,
          indicador_bieno_servicio: 2,
          unidad_medida: "43"
        ),
      "subtotales" => [],
      "descuentosORecargos" => [],
      "paginacion" => [],
      "fechaHoraFirma" => build_fecha_hora_firma(payload, opts)
    }
    |> normalize_currency_fields()
  end

  @spec map_e44(map(), Company.t(), keyword()) :: map()
  def map_e44(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    %{
      "encabezado" => %{
        "version" => "1.0",
        "idDoc" => build_id_doc_e44(payload, opts),
        "emisor" => build_emisor(payload, company),
        "comprador" => build_comprador(payload),
        "totales" => build_totales_e44(payload)
      },
      "detallesItems" =>
        build_detalles_items(payload,
          indicador_facturacion: 4,
          unidad_medida: "15"
        ),
      "subtotales" => [],
      "descuentosORecargos" => build_descuentos_o_recargos(payload),
      "paginacion" => [],
      "fechaHoraFirma" => build_fecha_hora_firma(payload, opts)
    }
    |> normalize_currency_fields()
  end

  @spec map_e45(map(), Company.t(), keyword()) :: map()
  def map_e45(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    %{
      "encabezado" => %{
        "version" => "1.0",
        "idDoc" => build_id_doc_e45(payload, opts),
        "emisor" => build_emisor(payload, company),
        "comprador" => build_comprador(payload),
        "informacionesAdicionales" => build_informaciones_adicionales(payload),
        "totales" => build_totales_e45(payload)
      },
      "detallesItems" => build_detalles_items_e45(payload),
      "subtotales" => [],
      "descuentosORecargos" => [],
      "paginacion" => [],
      "fechaHoraFirma" => build_fecha_hora_firma(payload, opts)
    }
    |> normalize_currency_fields()
  end

  @spec map_e46(map(), Company.t(), keyword()) :: map()
  def map_e46(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    %{
      "encabezado" => %{
        "version" => "1.0",
        "idDoc" => build_id_doc_e46(payload, opts),
        "emisor" => build_emisor_e46(payload, company),
        "comprador" => build_comprador_e46(payload),
        "informacionesAdicionales" => build_informaciones_adicionales_e46(payload),
        "transporte" => build_transporte_e46(payload),
        "totales" => build_totales_e46(payload)
      },
      "detallesItems" => build_detalles_items_e46(payload),
      "subtotales" => [],
      "descuentosORecargos" => [],
      "paginacion" => [],
      "fechaHoraFirma" => build_fecha_hora_firma(payload, opts)
    }
    |> normalize_currency_fields()
  end

  @spec map_e47(map(), Company.t(), keyword()) :: map()
  def map_e47(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    %{
      "encabezado" => %{
        "version" => "1.0",
        "idDoc" => build_id_doc_e47(payload, opts),
        "emisor" => build_emisor_e47_from_company(payload, company),
        "comprador" => build_comprador_e47_from_supplier(payload),
        "totales" => build_totales_e47(payload),
        "otraMoneda" => build_otra_moneda_e47(payload)
      },
      "detallesItems" => build_detalles_items_e47(payload),
      "subtotales" => build_subtotales_e47(payload),
      "descuentosORecargos" => [],
      "paginacion" => [],
      "fechaHoraFirma" => build_fecha_hora_firma(payload, opts)
    }
    |> normalize_currency_fields()
  end

  @spec map_invoice(map(), Company.t(), keyword()) :: map()
  def map_invoice(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    case resolve_tipo_ecf(payload, opts) do
      41 -> map_e41(payload, company, opts)
      43 -> map_e43(payload, company, opts)
      44 -> map_e44(payload, company, opts)
      45 -> map_e45(payload, company, opts)
      46 -> map_e46(payload, company, opts)
      47 -> map_e47(payload, company, opts)
      32 -> map_e32(payload, company, opts)
      33 -> map_e33(payload, company, opts)
      34 -> map_e34(payload, company, opts)
      _ -> map_e31(payload, company, opts)
    end
  end

  defp build_id_doc_e31(payload, monto_total, tipoeCF, opts) do
    %{
      "tipoeCF" => tipoeCF,
      "encf" => string_or_empty(Keyword.get(opts, :e_doc)),
      "fechaVencimientoSecuencia" => @fecha_vencimiento_secuencia,
      "indicadorMontoGravado" => indicador_monto_gravado(payload),
      "tipoIngresos" => "01",
      "tipoPago" => tipo_pago(payload),
      "tablaFormasPago" => [
        %{
          "formaPago" => 2,
          "montoPago" => monto_total
        }
      ]
    }
  end

  defp build_id_doc_e33(payload, monto_total, opts) do
    %{
      "tipoeCF" => 33,
      "encf" => string_or_empty(Keyword.get(opts, :e_doc)),
      "fechaVencimientoSecuencia" => @fecha_vencimiento_secuencia,
      "tipoIngresos" => "01",
      "tipoPago" => tipo_pago(payload),
      "tablaFormasPago" => [
        %{
          "formaPago" => 2,
          "montoPago" => monto_total
        }
      ]
    }
  end

  defp build_id_doc_e34(payload, opts) do
    %{
      "tipoeCF" => 34,
      "encf" => string_or_empty(Keyword.get(opts, :e_doc)),
      "indicadorNotaCredito" => "0",
      "indicadorMontoGravado" => indicador_monto_gravado(payload),
      "tipoIngresos" => "01",
      "tipoPago" => tipo_pago(payload),
      "tablaFormasPago" => []
    }
  end

  defp build_id_doc_e41(payload, opts) do
    %{
      "tipoeCF" => 41,
      "encf" => string_or_empty(Keyword.get(opts, :e_doc)),
      "fechaVencimientoSecuencia" => @fecha_vencimiento_secuencia,
      "indicadorMontoGravado" => indicador_monto_gravado(payload),
      "FechaLimitePago" => fecha_limite_pago(payload, 41),
      "tipoPago" => tipo_pago(payload),
      "tablaFormasPago" => [
        %{
          "formaPago" => 2,
          "montoPago" => amount_total(payload)
        }
      ]
    }
  end

  defp build_id_doc_e43(_payload, opts) do
    %{
      "tipoeCF" => 43,
      "encf" => string_or_empty(Keyword.get(opts, :e_doc)),
      "fechaVencimientoSecuencia" => @fecha_vencimiento_secuencia,
      "tablaFormasPago" => []
    }
  end

  defp build_id_doc_e44(payload, opts) do
    %{
      "tipoeCF" => 44,
      "encf" => string_or_empty(Keyword.get(opts, :e_doc)),
      "fechaVencimientoSecuencia" => @fecha_vencimiento_secuencia,
      "tipoIngresos" => "01",
      "tipoPago" => tipo_pago(payload),
      "tablaFormasPago" => [
        %{
          "formaPago" => 2,
          "montoPago" => amount_total(payload)
        }
      ],
      "tipoCuentaPago" => value_as_string(payload, ["tipoCuentaPago", "tipo_cuenta_pago"], "CT"),
      "numeroCuentaPago" =>
        value_as_string(payload, ["numeroCuentaPago", "numero_cuenta_pago"], ""),
      "bancoPago" => value_as_string(payload, ["bancoPago", "banco_pago"], "")
    }
  end

  defp build_id_doc_e45(payload, opts) do
    %{
      "tipoeCF" => 45,
      "encf" => string_or_empty(Keyword.get(opts, :e_doc)),
      "fechaVencimientoSecuencia" => @fecha_vencimiento_secuencia,
      "indicadorMontoGravado" => indicador_monto_gravado(payload),
      "tipoIngresos" => "01",
      "tipoPago" => tipo_pago(payload),
      "tablaFormasPago" => []
    }
  end

  defp build_id_doc_e46(payload, opts) do
    %{
      "tipoeCF" => 46,
      "encf" => string_or_empty(Keyword.get(opts, :e_doc)),
      "fechaVencimientoSecuencia" => @fecha_vencimiento_secuencia,
      "tipoIngresos" => "01",
      "tipoPago" => tipo_pago(payload),
      "fechaLimitePago" =>
        format_date(
          value_from_keys(payload, ["fechaLimitePago", "fecha_limite_pago", "invoice_date_due"])
        ),
      "terminoPago" => value_as_string(payload, ["terminoPago", "termino_pago"], ""),
      "tablaFormasPago" => [
        %{
          "formaPago" => 2,
          "montoPago" => amount_total(payload)
        }
      ]
    }
  end

  defp build_id_doc_e47(payload, opts) do
    %{
      "tipoeCF" => 47,
      "encf" => string_or_empty(Keyword.get(opts, :e_doc)),
      "fechaVencimientoSecuencia" => @fecha_vencimiento_secuencia,
      "tablaFormasPago" => [],
      "FechaLimitePago" => fecha_limite_pago(payload, 47),
      "numeroCuentaPago" =>
        value_as_string(payload, ["numeroCuentaPago", "numero_cuenta_pago"], ""),
      "bancoPago" => value_as_string(payload, ["bancoPago", "banco_pago"], "")
    }
  end

  defp build_emisor(payload, %Company{} = company) do
    %{
      "rncEmisor" => rnc_or_empty(company_field(company, :rnc)),
      "razonSocialEmisor" => string_or_empty(company_field(company, :company_name)),
      "nombreComercial" => string_or_empty(company_field(company, :company_name)),
      "direccionEmisor" =>
        value_or_default(
          company_address(company),
          "N/A"
        ),
      "tablaTelefonoEmisor" => company_phone_list(company),
      "correoEmisor" => string_or_empty(company_email(company)),
      "webSite" => string_or_empty(company_website(company)),
      "codigoVendedor" => string_or_empty(company_field(company, :codigo_vendedor)),
      "numeroFacturaInterna" => string_or_empty(payload_value(payload, "payment_reference")),
      # "numeroPedidoInterno" =>
      #   string_or_empty(
      #     payload_value(payload, "invoice_origin") ||
      #       payload_value(payload, "payment_reference") || payload_value(payload, "name")
      #   ),
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

  defp build_totales_e31(payload) do
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

  defp build_totales_e32(payload) do
    %{
      "montoExento" => amount_exempt(payload),
      "impuestosAdicionales" => [],
      "montoTotal" => amount_total(payload)
    }
  end

  defp build_totales_e43(payload) do
    monto_exento = amount_exempt(payload)

    %{
      "montoExento" => monto_exento,
      "impuestosAdicionales" => [],
      "montoTotal" => monto_exento
    }
  end

  defp build_informacion_referencia_e33(payload) do
    %{
      "ncfModificado" => modified_ncf(payload),
      "fechaNCFModificado" => modified_ncf_date(payload),
      "codigoModificacion" => modification_code(payload, 3)
    }
  end

  defp build_informacion_referencia_e34(payload) do
    %{
      "ncfModificado" => modified_ncf(payload),
      "fechaNCFModificado" => modified_ncf_date(payload),
      "codigoModificacion" => modification_code(payload, 2),
      "razonModificacion" => modification_reason(payload)
    }
  end

  defp build_emisor_e41_from_company(payload, %Company{} = company) do
    %{
      "rncEmisor" => rnc_or_empty(company_field(company, :rnc)),
      "razonSocialEmisor" => string_or_empty(company_field(company, :company_name)),
      "direccionEmisor" => value_or_default(company_address(company), "N/A"),
      "tablaTelefonoEmisor" => company_phone_list(company),
      "fechaEmision" => format_date(payload_value(payload, "invoice_date"))
    }
  end

  defp build_emisor_e43_from_company(payload, %Company{} = company) do
    %{
      "rncEmisor" => rnc_or_empty(company_field(company, :rnc)),
      "razonSocialEmisor" => string_or_empty(company_field(company, :company_name)),
      "nombreComercial" => string_or_empty(company_field(company, :company_name)),
      "direccionEmisor" => value_or_default(company_address(company), "N/A"),
      "tablaTelefonoEmisor" => company_phone_list(company),
      "correoEmisor" => string_or_empty(company_email(company)),
      "webSite" => string_or_empty(company_website(company)),
      "numeroFacturaInterna" => string_or_empty(payload_value(payload, "payment_reference")),
      "numeroPedidoInterno" => internal_order_number(payload),
      "fechaEmision" => format_date(payload_value(payload, "invoice_date"))
    }
  end

  defp build_emisor_e47_from_company(payload, %Company{} = company) do
    build_emisor_e43_from_company(payload, company)
  end

  defp build_emisor_e46(payload, %Company{} = company) do
    payload
    |> build_emisor(company)
    |> Map.take([
      "rncEmisor",
      "razonSocialEmisor",
      "nombreComercial",
      "direccionEmisor",
      "tablaTelefonoEmisor",
      "correoEmisor",
      "webSite",
      "codigoVendedor",
      "numeroFacturaInterna",
      "numeroPedidoInterno",
      "fechaEmision"
    ])
  end

  defp build_comprador_e41_from_supplier(payload) do
    %{
      "rncComprador" =>
        rnc_or_empty(
          value_from_keys(payload, ["rncComprador", "rnc_comprador", "rncEmisor", "rnc_emisor"]) ||
            customer_tax_id(payload)
        ),
      "razonSocialComprador" =>
        string_or_empty(
          value_from_keys(payload, [
            "razonSocialComprador",
            "razon_social_comprador",
            "razonSocialEmisor",
            "razon_social_emisor"
          ]) || customer_name(payload)
        ),
      "correoComprador" =>
        string_or_empty(
          value_from_keys(payload, ["correoComprador", "correo_comprador", "partner_email"])
        ),
      "direccionComprador" =>
        direccion_comprador(
          value_from_keys(payload, [
            "direccionComprador",
            "direccion_comprador",
            "partner_address",
            "direccionEmisor",
            "direccion_emisor"
          ])
        ),
      "municipioComprador" =>
        value_or_default(payload_value(payload, "municipio_comprador"), "010101"),
      "provinciaComprador" =>
        value_or_default(payload_value(payload, "provincia_comprador"), "010000")
    }
  end

  defp build_comprador_e46(payload) do
    base =
      payload
      |> build_comprador()
      |> Map.take([
        "rncComprador",
        "razonSocialComprador",
        "contactoComprador",
        "correoComprador",
        "direccionComprador",
        "municipioComprador",
        "provinciaComprador",
        "fechaEntrega",
        "fechaOrdenCompra",
        "numeroOrdenCompra",
        "codigoInternoComprador"
      ])

    Map.merge(base, %{
      "contactoEntrega" => value_as_string(payload, ["contactoEntrega", "contacto_entrega"], ""),
      "direccionEntrega" =>
        value_as_string(payload, ["direccionEntrega", "direccion_entrega"], ""),
      "telefonoAdicional" =>
        value_as_string(payload, ["telefonoAdicional", "telefono_adicional"], "")
    })
  end

  defp build_comprador_e47_from_supplier(payload) do
    %{
      "identificadorExtranjero" => foreign_buyer_identifier(payload),
      "razonSocialComprador" =>
        string_or_empty(
          value_from_keys(payload, [
            "razonSocialComprador",
            "razon_social_comprador",
            "razonSocialEmisor",
            "razon_social_emisor"
          ]) || customer_name(payload)
        )
    }
  end

  defp build_totales_e41(payload) do
    total_itbis = amount_tax(payload)

    total_isr_retencion =
      numeric(value_from_keys(payload, ["totalISRRetencion", "total_isr_retencion"])) || 0

    total_itbis_retenido =
      numeric(value_from_keys(payload, ["totalITBISRetenido", "total_itbis_retenido"])) ||
        total_itbis

    monto_total = amount_total(payload)

    %{
      "montoGravadoTotal" => amount_untaxed(payload),
      "montoGravadoI1" => amount_untaxed(payload),
      "itbis1" => itbis_rate(payload, amount_untaxed(payload), total_itbis),
      "totalITBIS" => total_itbis,
      "totalITBIS1" => total_itbis,
      "impuestosAdicionales" => [],
      "montoTotal" => monto_total,
      "valorPagar" =>
        numeric(value_from_keys(payload, ["valorPagar", "valor_pagar"])) || monto_total,
      "totalITBISRetenido" => total_itbis_retenido,
      "totalISRRetencion" => total_isr_retencion
    }
  end

  defp build_totales_e44(payload) do
    monto_total = amount_total(payload)

    %{
      "montoExento" => amount_exempt(payload),
      "impuestosAdicionales" => [],
      "montoTotal" => monto_total,
      "valorPagar" =>
        numeric(value_from_keys(payload, ["valorPagar", "valor_pagar"])) || monto_total
    }
  end

  defp build_totales_e45(payload) do
    monto_total = amount_total(payload)

    %{
      "montoGravadoTotal" => amount_untaxed(payload),
      "montoGravadoI1" => amount_untaxed(payload),
      "itbis1" => itbis_rate(payload, amount_untaxed(payload), amount_tax(payload)),
      "totalITBIS" => amount_tax(payload),
      "totalITBIS1" => amount_tax(payload),
      "impuestosAdicionales" => [],
      "montoTotal" => monto_total,
      "valorPagar" =>
        numeric(value_from_keys(payload, ["valorPagar", "valor_pagar"])) || monto_total
    }
  end

  defp build_totales_e46(payload) do
    monto_total = amount_total(payload)

    %{
      "montoGravadoTotal" => amount_untaxed(payload),
      "montoGravadoI3" => amount_untaxed(payload),
      "itbis3" => 0,
      "totalITBIS" => 0,
      "totalITBIS3" => 0,
      "impuestosAdicionales" => [],
      "montoTotal" => monto_total
    }
  end

  defp build_totales_e47(payload) do
    %{
      "montoExento" => amount_exempt(payload),
      "impuestosAdicionales" => [],
      "montoTotal" => amount_total(payload),
      "totalISRRetencion" =>
        numeric(value_from_keys(payload, ["totalISRRetencion", "total_isr_retencion"])) || 0
    }
  end

  defp build_informaciones_adicionales_e46(payload) do
    %{
      "fechaEmbarque" =>
        format_date(value_from_keys(payload, ["fechaEmbarque", "fecha_embarque"])),
      "numeroEmbarque" => value_as_string(payload, ["numeroEmbarque", "numero_embarque"], ""),
      "numeroContenedor" =>
        value_as_string(payload, ["numeroContenedor", "numero_contenedor"], ""),
      "numeroReferencia" => payload_value(payload, "_id") || payload_value(payload, "id") || "",
      "pesoBruto" => numeric(value_from_keys(payload, ["pesoBruto", "peso_bruto"])) || 0,
      "pesoNeto" => numeric(value_from_keys(payload, ["pesoNeto", "peso_neto"])) || 0,
      "unidadPesoBruto" => value_as_string(payload, ["unidadPesoBruto", "unidad_peso_bruto"], ""),
      "unidadPesoNeto" => value_as_string(payload, ["unidadPesoNeto", "unidad_peso_neto"], ""),
      "cantidadBulto" =>
        numeric(value_from_keys(payload, ["cantidadBulto", "cantidad_bulto"])) || 0,
      "unidadBulto" => value_as_string(payload, ["unidadBulto", "unidad_bulto"], ""),
      "volumenBulto" => numeric(value_from_keys(payload, ["volumenBulto", "volumen_bulto"])) || 0,
      "unidadVolumen" => value_as_string(payload, ["unidadVolumen", "unidad_volumen"], "")
    }
  end

  defp build_transporte_e46(payload) do
    %{
      "numeroAlbaran" => value_as_string(payload, ["numeroAlbaran", "numero_albaran"], "")
    }
  end

  defp build_otra_moneda_e47(payload) do
    explicit_exchange_rate? = exchange_rate_provided?(payload)
    exchange_rate = exchange_rate(payload, @default_e47_exchange_rate)

    monto_exento_otra =
      numeric(value_from_keys(payload, ["montoExentoOtraMoneda", "monto_exento_otra_moneda"]))

    monto_total_otra =
      numeric(value_from_keys(payload, ["montoTotalOtraMoneda", "monto_total_otra_moneda"]))

    %{
      "tipoMoneda" =>
        value_as_string(payload, ["tipoMoneda", "tipo_moneda", "currency"], @default_e47_currency),
      "tipoCambio" => exchange_rate,
      "montoExentoOtraMoneda" =>
        monto_exento_otra ||
          e47_foreign_currency_amount(
            amount_exempt(payload),
            exchange_rate,
            explicit_exchange_rate?
          ),
      "impuestosAdicionalesOtraMoneda" =>
        list_or_empty(
          value_from_keys(payload, [
            "impuestosAdicionalesOtraMoneda",
            "impuestos_adicionales_otra_moneda"
          ])
        ),
      "montoTotalOtraMoneda" =>
        monto_total_otra ||
          e47_foreign_currency_amount(
            amount_total(payload),
            exchange_rate,
            explicit_exchange_rate?
          )
    }
  end

  defp build_descuentos_o_recargos(payload) do
    payload
    |> value_from_keys(["descuentosORecargos", "descuentos_o_recargos"])
    |> list_or_empty()
    |> Enum.map(fn entry ->
      %{
        "numeroLinea" => numeric(value_from_keys(entry, ["numeroLinea", "numero_linea"])) || 0,
        "tipoAjuste" => value_as_string(entry, ["tipoAjuste", "tipo_ajuste"], ""),
        "descripcionDescuentooRecargo" =>
          value_as_string(
            entry,
            ["descripcionDescuentooRecargo", "descripcion_descuentoo_recargo"],
            ""
          ),
        "tipoValor" => value_as_string(entry, ["tipoValor", "tipo_valor"], ""),
        "valorDescuentooRecargo" =>
          numeric(value_from_keys(entry, ["valorDescuentooRecargo", "valor_descuentoo_recargo"])) ||
            0,
        "montoDescuentooRecargo" =>
          numeric(value_from_keys(entry, ["montoDescuentooRecargo", "monto_descuentoo_recargo"])) ||
            0,
        "indicadorFacturacionDescuentooRecargo" =>
          numeric(
            value_from_keys(
              entry,
              [
                "indicadorFacturacionDescuentooRecargo",
                "indicador_facturacion_descuentoo_recargo"
              ]
            )
          ) || 0
      }
    end)
  end

  defp build_subtotales_e47(payload) do
    provided =
      payload
      |> value_from_keys(["subtotales", "sub_totales"])
      |> list_or_empty()

    if provided == [] do
      [
        %{
          "numeroSubTotal" => 1,
          "descripcionSubtotal" => "N/A",
          "orden" => 1,
          "subTotalExento" => amount_exempt(payload),
          "montoSubTotal" => amount_total(payload),
          "lineas" => max(length(invoice_items(payload)), 1)
        }
      ]
    else
      Enum.map(provided, fn subtotal ->
        %{
          "numeroSubTotal" => numeric(payload_value(subtotal, "numeroSubTotal")) || 0,
          "descripcionSubtotal" =>
            value_as_string(subtotal, ["descripcionSubtotal", "descripcion_subtotal"], ""),
          "orden" => numeric(payload_value(subtotal, "orden")) || 0,
          "subTotalExento" =>
            numeric(value_from_keys(subtotal, ["subTotalExento", "sub_total_exento"])) || 0,
          "montoSubTotal" =>
            numeric(value_from_keys(subtotal, ["montoSubTotal", "monto_sub_total"])) || 0,
          "lineas" => numeric(payload_value(subtotal, "lineas")) || 0
        }
      end)
    end
  end

  defp build_detalles_items_e41(payload) do
    indicador_facturacion = payload_facturation_indicator(payload)

    itbis_retenido =
      numeric(value_from_keys(payload, ["totalITBISRetenido", "total_itbis_retenido"])) ||
        amount_tax(payload)

    isr_retenido =
      numeric(value_from_keys(payload, ["totalISRRetencion", "total_isr_retencion"])) || 0

    payload
    |> invoice_items()
    |> Enum.with_index(1)
    |> Enum.map(fn {item, index} ->
      quantity = item_quantity(item)
      unit_price = item_unit_price(item)
      amount = item_amount(item, quantity, unit_price)

      %{
        "numeroLinea" => index,
        "tablaCodigosItem" => [],
        "indicadorFacturacion" => indicador_facturacion,
        "retencion" => %{
          "indicadorAgenteRetencionoPercepcion" => 1,
          "montoITBISRetenido" =>
            numeric(value_from_keys(item, ["montoITBISRetenido", "monto_itbis_retenido"])) ||
              itbis_retenido,
          "montoISRRetenido" =>
            numeric(value_from_keys(item, ["montoISRRetenido", "monto_isr_retenido"])) ||
              isr_retenido
        },
        "nombreItem" => item_name(item),
        "indicadorBienoServicio" => item_bieno_servicio_indicator(item, 2),
        "descripcionItem" => item_description(item),
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

  defp build_detalles_items_e45(payload) do
    indicador_facturacion = payload_facturation_indicator(payload)

    payload
    |> invoice_items()
    |> Enum.with_index(1)
    |> Enum.map(fn {item, index} ->
      quantity = item_quantity(item)
      unit_price = item_unit_price(item)
      amount = item_amount(item, quantity, unit_price)

      %{
        "numeroLinea" => index,
        "tablaCodigosItem" => [],
        "indicadorFacturacion" => indicador_facturacion,
        "nombreItem" => item_name(item),
        "indicadorBienoServicio" => item_bieno_servicio_indicator(item, 2),
        "descripcionItem" => item_description(item),
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

  defp build_detalles_items_e46(payload) do
    payload
    |> invoice_items()
    |> Enum.with_index(1)
    |> Enum.map(fn {item, index} ->
      quantity = item_quantity(item)
      unit_price = item_unit_price(item)
      amount = item_amount(item, quantity, unit_price)

      %{
        "numeroLinea" => index,
        "tablaCodigosItem" => build_tabla_codigos_item_e46(item),
        "indicadorFacturacion" => 3,
        "nombreItem" => item_name(item),
        "indicadorBienoServicio" => item_bieno_servicio_indicator(item, 1),
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

  defp build_detalles_items_e47(payload) do
    explicit_exchange_rate? = exchange_rate_provided?(payload)
    exchange_rate = exchange_rate(payload, @default_e47_exchange_rate)

    isr_retenido =
      numeric(value_from_keys(payload, ["totalISRRetencion", "total_isr_retencion"])) || 0

    payload
    |> invoice_items()
    |> Enum.with_index(1)
    |> Enum.map(fn {item, index} ->
      quantity = item_quantity(item)
      unit_price = item_unit_price(item)
      amount = item_amount(item, quantity, unit_price)

      %{
        "numeroLinea" => index,
        "tablaCodigosItem" => [],
        "indicadorFacturacion" => 4,
        "retencion" => %{
          "indicadorAgenteRetencionoPercepcion" => 1,
          "montoISRRetenido" =>
            numeric(value_from_keys(item, ["montoISRRetenido", "monto_isr_retenido"])) ||
              isr_retenido
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
          "precioOtraMoneda" =>
            numeric(value_from_keys(item, ["precioOtraMoneda", "precio_otra_moneda"])) ||
              e47_detail_foreign_currency_amount(
                unit_price,
                exchange_rate,
                explicit_exchange_rate?
              ),
          "montoItemOtraMoneda" =>
            numeric(value_from_keys(item, ["montoItemOtraMoneda", "monto_item_otra_moneda"])) ||
              e47_detail_foreign_currency_amount(amount, exchange_rate, explicit_exchange_rate?)
        },
        "montoItem" => amount
      }
    end)
  end

  defp build_tabla_codigos_item_e46(item) do
    provided =
      item
      |> value_from_keys(["tablaCodigosItem", "tabla_codigos_item"])
      |> list_or_empty()

    if provided == [] do
      codigo = value_as_string(item, ["codigoItem", "codigo_item"], item_code(item))

      if codigo == "" do
        []
      else
        [
          %{
            "tipoCodigo" => value_as_string(item, ["tipoCodigo", "tipo_codigo"], "INTERNA"),
            "codigoItem" => codigo
          }
        ]
      end
    else
      Enum.map(provided, fn code ->
        %{
          "tipoCodigo" => value_as_string(code, ["tipoCodigo", "tipo_codigo"], ""),
          "codigoItem" => value_as_string(code, ["codigoItem", "codigo_item"], "")
        }
      end)
    end
  end

  defp build_detalles_items(payload, opts \\ []) do
    indicador_facturacion = Keyword.get(opts, :indicador_facturacion)
    indicador_bieno_servicio = Keyword.get(opts, :indicador_bieno_servicio, 1)

    payload
    |> invoice_items()
    |> Enum.with_index(1)
    |> Enum.map(fn {item, index} ->
      quantity = item_quantity(item)
      unit_price = item_unit_price(item)
      amount = item_amount(item, quantity, unit_price)

      %{
        "numeroLinea" => index,
        "tablaCodigosItem" => [],
        "indicadorFacturacion" => indicador_facturacion || payload_facturation_indicator(payload),
        "nombreItem" => item_name(item),
        "indicadorBienoServicio" => item_bieno_servicio_indicator(item, indicador_bieno_servicio),
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

  defp build_fecha_hora_firma(payload, opts) do
    value =
      payload_value(payload, "fechaHoraFirma") ||
        payload_value(payload, "fecha_hora_firma") || Keyword.get(opts, :fecha_hora_firma) ||
        DateTime.utc_now(:second)

    format_datetime(value)
  end

  defp normalize_item(%{} = item), do: item
  defp normalize_item(_), do: %{}

  defp tipo_pago(payload) do
    payment_term_id =
      payload
      |> payload_value("invoice_payment_term_id")
      |> odoo_reference_id()

    invoice_date =
      payload
      |> payload_value("invoice_date")
      |> format_date()

    invoice_date_due =
      payload
      |> payload_value("invoice_date_due")
      |> format_date()

    if invoice_date != "" and invoice_date_due != "" do
      if invoice_date_due == invoice_date, do: 1, else: 2
    else
      if payment_term_id == 1, do: 1, else: 2
    end
  end

  defp fecha_limite_pago(payload, tipo_ecf) do
    explicit_date =
      payload
      |> value_from_keys(["FechaLimitePago", "fechaLimitePago", "fecha_limite_pago"])
      |> format_date()

    if explicit_date != "" do
      explicit_date
    else
      payload
      |> payload_value("invoice_date_due")
      |> add_days_to_date(Map.get(@fecha_limite_pago_offsets, tipo_ecf, 0))
      |> format_date()
    end
  end

  defp add_days_to_date(value, days) do
    with date_text when is_binary(date_text) <- value,
         {:ok, date} <- Date.from_iso8601(String.trim(date_text)) do
      Date.add(date, days)
    else
      _ -> value
    end
  end

  defp indicador_monto_gravado(payload) do
    if explicit_tax_groups?(payload), do: 0, else: 1
  end

  defp explicit_tax_groups?(payload) do
    payload
    |> payload_value("tax_totals")
    |> case do
      %{} = totals ->
        totals
        |> Map.get("subtotals", [])
        |> List.wrap()
        |> Enum.any?(fn subtotal ->
          subtotal
          |> Map.get("tax_groups", [])
          |> List.wrap()
          |> Enum.any?()
        end)

      _ ->
        false
    end
  end

  defp internal_order_number(payload) do
    payload
    |> value_from_keys([
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
    |> value_from_keys([
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

  defp direccion_comprador(value) do
    value
    |> string_or_empty()
    |> String.slice(0, @direccion_comprador_max_length)
  end

  defp payload_facturation_indicator(payload) do
    if zero_amount?(amount_tax(payload)), do: 4, else: 1
  end

  defp item_bieno_servicio_indicator(%{} = item, default) do
    type =
      item
      |> value_from_keys(["type", "product_type", "detailed_type"])
      |> string_or_empty()
      |> String.trim()
      |> String.downcase()

    cond do
      type == "service" -> 2
      type == "" -> default
      true -> 1
    end
  end

  defp item_bieno_servicio_indicator(_item, default), do: default

  defp item_name(item) do
    (payload_value(item, "name") || tuple_label(payload_value(item, "product_id")) || "")
    |> strip_bracket_prefix()
  end

  defp item_description(item) do
    value_as_string(item, ["descripcionItem", "descripcion_item", "description"], item_name(item))
  end

  defp item_code(item) do
    value_as_string(
      item,
      ["default_code", "codigo_item"],
      extract_bracket_code(payload_value(item, "name"))
    )
  end

  defp item_quantity(item), do: numeric(payload_value(item, "quantity")) || 0

  defp item_unit_price(item) do
    numeric(payload_value(item, "price_unit")) ||
      derived_unit_price(
        numeric(payload_value(item, "price_subtotal")),
        numeric(payload_value(item, "quantity"))
      ) || 0
  end

  defp item_amount(item, quantity, unit_price) do
    numeric(payload_value(item, "price_subtotal")) ||
      numeric(payload_value(item, "debit")) ||
      numeric(payload_value(item, "credit")) ||
      quantity * unit_price
  end

  defp derived_unit_price(nil, _quantity), do: nil
  defp derived_unit_price(_amount, quantity) when quantity in [0, 0.0, nil], do: nil
  defp derived_unit_price(amount, quantity), do: amount / quantity

  defp amount_total(payload) do
    numeric(payload_value(payload, "amount_total")) || tax_totals_value(payload, "total_amount") ||
      0
  end

  defp amount_untaxed(payload) do
    numeric(payload_value(payload, "amount_untaxed")) ||
      tax_totals_value(payload, "base_amount") ||
      max(amount_total(payload) - amount_tax(payload), 0)
  end

  defp amount_tax(payload) do
    numeric(value_from_keys(payload, ["amount_tax", "tax_amount"])) ||
      tax_totals_value(payload, "tax_amount") || 0
  end

  defp amount_exempt(payload) do
    numeric(payload_value(payload, "amount_untaxed")) ||
      tax_totals_value(payload, "base_amount") ||
      amount_total(payload)
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

  defp customer_name(payload) do
    payload_value(payload, "razonSocialComprador") ||
      payload_value(payload, "razon_social_comprador") ||
      payload_value(payload, "invoice_partner_display_name") ||
      tuple_label(payload_value(payload, "commercial_partner_id")) ||
      tuple_label(payload_value(payload, "partner_id"))
  end

  defp resolve_tipo_ecf(payload, opts) do
    Keyword.get(opts, :e_doc)
    |> parse_tipo_ecf()
    |> case do
      nil ->
        (payload_value(payload, "x_studio_e_doc_inv") ||
           payload_value(payload, "x_studio_e_doc_bill"))
        |> parse_tipo_ecf()

      tipo_ecf ->
        tipo_ecf
    end
  end

  defp parse_tipo_ecf(value) when is_binary(value) do
    case Regex.run(~r/^E?(\d{2})/, String.trim(value)) do
      [_, digits] -> String.to_integer(digits)
      _ -> nil
    end
  end

  defp parse_tipo_ecf(_), do: nil

  defp value_from_keys(payload, keys) when is_map(payload) and is_list(keys) do
    Enum.find_value(keys, &payload_value(payload, &1))
  end

  defp value_from_keys(_, _), do: nil

  defp value_as_string(payload, keys, default)

  defp value_as_string(payload, keys, default) when is_list(keys) do
    payload
    |> value_from_keys(keys)
    |> case do
      nil -> default
      false -> default
      value -> string_or_empty(value)
    end
  end

  defp value_as_string(value, _keys, default) when is_nil(value) or value == false, do: default

  defp value_as_string(value, _keys, _default) do
    string_or_empty(value)
  end

  defp list_or_empty(value) when is_list(value), do: value
  defp list_or_empty(_), do: []

  defp exchange_rate(payload, default) do
    case numeric(value_from_keys(payload, ["tipoCambio", "tipo_cambio", "exchange_rate"])) do
      nil -> default
      value -> value
    end
  end

  defp exchange_rate_provided?(payload) do
    not is_nil(numeric(value_from_keys(payload, ["tipoCambio", "tipo_cambio", "exchange_rate"])))
  end

  defp e47_foreign_currency_amount(amount, rate, true), do: safe_div(amount, rate)

  defp e47_foreign_currency_amount(amount, rate, false) do
    amount
    |> safe_div(rate)
    |> trunc_to_tenths()
  end

  defp e47_detail_foreign_currency_amount(amount, rate, true), do: safe_div(amount, rate)
  defp e47_detail_foreign_currency_amount(_amount, _rate, false), do: 0

  defp trunc_to_tenths(value) when is_number(value), do: trunc(value * 10) / 10
  defp trunc_to_tenths(_value), do: 0

  defp safe_div(_amount, rate) when rate in [0, 0.0], do: 0
  defp safe_div(nil, _rate), do: 0
  defp safe_div(amount, rate), do: amount / rate

  defp invoice_items(payload) do
    payload
    |> payload_value("invoice_items")
    |> List.wrap()
    |> Enum.map(&normalize_item/1)
  end

  defp modified_ncf(payload) do
    [
      "reversed_entry_ref",
      "reversedEntryRef",
      "reversed_invoice_ref",
      "ncfModificado",
      "ncf_modificado",
      "ncf_modifcado",
      "x_studio_ncf_modificado",
      "l10n_do_origin_ncf",
      "invoice_origin_ncf",
      "reference_ncf"
    ]
    |> Enum.find_value(&payload_value(payload, &1))
    |> string_or_empty()
  end

  defp modified_ncf_date(payload) do
    [
      "fechaNCFModificado",
      "fecha_ncf_modificado",
      "x_studio_fecha_ncf_modificado",
      "invoice_origin_date",
      "ref_date",
      "invoice_date"
    ]
    |> Enum.find_value(&payload_value(payload, &1))
    |> format_date()
  end

  defp modification_code(payload, default) do
    value =
      ["codigoModificacion", "codigo_modificacion", "x_studio_codigo_modificacion"]
      |> Enum.find_value(&payload_value(payload, &1))

    numeric(value)
    |> case do
      nil -> default
      value when is_integer(value) -> value
      value when is_float(value) -> trunc(value)
      _ -> default
    end
  end

  defp modification_reason(payload) do
    [
      "ref",
      "razonModificacion",
      "razon_modificacion",
      "x_studio_razon_modificacion",
      "reason",
      "ref_reason"
    ]
    |> Enum.find_value(&payload_value(payload, &1))
    |> string_or_empty()
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
    |> Enum.find_value(fn key ->
      payload
      |> payload_value(key)
      |> normalize_vat()
    end)
  end

  defp line_tax_id(%{} = line) do
    [
      "partner_vat",
      "vat",
      "rnc",
      "tax_id",
      "customer_tax_id"
    ]
    |> Enum.find_value(fn key ->
      line
      |> payload_value(key)
      |> normalize_vat()
    end)
  end

  defp line_tax_id(_), do: nil

  defp normalize_vat(nil), do: nil
  defp normalize_vat(false), do: nil
  defp normalize_vat(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_vat(value) when is_float(value), do: value |> trunc() |> Integer.to_string()

  defp normalize_vat(value) when is_binary(value) do
    digits = Regex.replace(~r/\D/, String.trim(value), "")
    if digits == "", do: nil, else: digits
  end

  defp normalize_vat(value) do
    case String.Chars.impl_for(value) do
      nil -> nil
      _impl -> value |> to_string() |> normalize_vat()
    end
  end

  defp tuple_label([_id, label]) when is_binary(label), do: label
  defp tuple_label(_), do: nil

  defp extract_bracket_code(value) when is_binary(value) do
    case Regex.run(~r/^\[([^\]]+)\]/, value) do
      [_, code] -> String.trim(code)
      _ -> ""
    end
  end

  defp extract_bracket_code(_), do: ""

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

  defp normalize_phone_candidates(_), do: []

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

    case digits do
      "" -> nil
      number -> number
    end
  end

  defp normalize_rnc(value), do: value |> to_string() |> normalize_rnc()

  defp value_or_default(value, default) do
    case string_or_empty(value) do
      "" -> default
      present -> present
    end
  end

  defp company_field(%Company{} = company, key) when is_atom(key), do: Map.get(company, key)

  defp payload_value(%{} = payload, key) when is_atom(key) do
    Map.get(payload, key) || Map.get(payload, Atom.to_string(key))
  end

  defp payload_value(%{} = payload, key) when is_binary(key), do: Map.get(payload, key)
  defp payload_value(_, _), do: nil

  defp odoo_reference_id([id | _]) when is_integer(id), do: id
  defp odoo_reference_id(id) when is_integer(id), do: id

  defp odoo_reference_id(id) when is_binary(id) do
    case Integer.parse(String.trim(id)) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp odoo_reference_id(_), do: nil

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

  defp normalize_currency_fields(value) when is_list(value) do
    Enum.map(value, &normalize_currency_fields/1)
  end

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

  defp pad_currency_decimals(value) do
    case String.split(value, ".", parts: 2) do
      [whole, fraction] ->
        "#{whole}.#{String.pad_trailing(String.slice(fraction, 0, 2), 2, "0")}"

      [whole] ->
        "#{whole}.00"
    end
  end

  defp string_or_empty(nil), do: ""
  defp string_or_empty(false), do: ""
  defp string_or_empty(value) when is_binary(value), do: String.trim(value)
  defp string_or_empty(value), do: to_string(value)
end