defmodule Edoc.Etaxcore.PayloadMapperTest do
  use ExUnit.Case, async: true

  alias Edoc.Accounts.Company
  alias Edoc.Etaxcore.PayloadMapper

  defp money(value) do
    {:ok, decimal} = Decimal.cast(value)

    decimal
    |> Decimal.round(2, :down)
    |> Decimal.to_string(:normal)
    |> case do
      normalized when is_binary(normalized) ->
        case String.split(normalized, ".", parts: 2) do
          [whole, fraction] ->
            "#{whole}.#{String.pad_trailing(String.slice(fraction, 0, 2), 2, "0")}"

          [whole] ->
            "#{whole}.00"
        end
    end
  end

  test "maps E31 odoo payload into the target etax shape" do
    payload = %{
      "_id" => 11_287,
      "amount_tax" => 459.0,
      "amount_total" => 3009.0,
      "amount_untaxed" => 2550.0,
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-02-24",
      "invoice_origin" => false,
      "invoice_partner_display_name" => "Santo Domingo Motors Company",
      "name" => "INV/2026/02/0008",
      "partner_id" => 316,
      "payment_reference" => "INV/2026/02/0008",
      "tax_totals" => %{
        "base_amount" => 2550.0,
        "tax_amount" => 459.0,
        "total_amount" => 3009.0,
        "subtotals" => [
          %{
            "tax_groups" => [
              %{
                "base_amount" => 2550.0,
                "tax_amount" => 459.0
              }
            ]
          }
        ]
      },
      "x_studio_e_doc_inv" => "E31",
      "invoice_items" => [
        %{
          "name" => "[BOTALMTRU] Botas de Trabajo de Almacen Trugard",
          "price_subtotal" => 2550.0,
          "price_unit" => 2550.0,
          "quantity" => 1.0,
          "tax_ids" => [3]
        }
      ]
    }

    company = %Company{
      company_name: "EDOC SRL",
      rnc: "123456789",
      odoo_url: "https://odoo.example.com"
    }

    mapped = PayloadMapper.map_e31(payload, company, e_doc: "E310000000001")

    assert Enum.sort(Map.keys(mapped)) == [
             "descuentosORecargos",
             "detallesItems",
             "encabezado",
             "fechaHoraFirma",
             "paginacion",
             "subtotales"
           ]

    assert mapped["encabezado"]["version"] == "1.0"
    assert mapped["encabezado"]["idDoc"]["tipoeCF"] == 31
    assert mapped["encabezado"]["idDoc"]["encf"] == "E310000000001"
    assert mapped["encabezado"]["idDoc"]["indicadorMontoGravado"] == 1
    assert mapped["encabezado"]["idDoc"]["tipoIngresos"] == "02"
    assert mapped["encabezado"]["idDoc"]["tipoPago"] == 2

    assert mapped["encabezado"]["idDoc"]["tablaFormasPago"] == [
             %{"formaPago" => 1, "montoPago" => money(3009.0)}
           ]

    assert mapped["encabezado"]["emisor"]["rncEmisor"] == 123_456_789
    assert mapped["encabezado"]["emisor"]["razonSocialEmisor"] == "EDOC SRL"
    assert mapped["encabezado"]["emisor"]["numeroFacturaInterna"] == "INV/2026/02/0008"

    assert mapped["encabezado"]["comprador"]["razonSocialComprador"] ==
             "Santo Domingo Motors Company"

    assert mapped["encabezado"]["comprador"]["codigoInternoComprador"] == "316"
    assert mapped["encabezado"]["informacionesAdicionales"]["numeroReferencia"] == 11_287

    assert mapped["encabezado"]["totales"] == %{
             "montoGravadoTotal" => money(2550.0),
             "montoGravadoI1" => money(2550.0),
             "itbis1" => 18,
             "totalITBIS" => money(459.0),
             "totalITBIS1" => money(459.0),
             "impuestosAdicionales" => [],
             "montoTotal" => money(3009.0)
           }

    assert [
             %{
               "numeroLinea" => 1,
               "indicadorFacturacion" => 1,
               "nombreItem" => "Botas de Trabajo de Almacen Trugard",
               "unidadMedida" => "43",
               "cantidadItem" => 1.0,
               "precioUnitarioItem" => money(2550.0),
               "montoItem" => money(2550.0)
             } = item
           ] = mapped["detallesItems"]

    assert item["tablaCodigosItem"] == []
    assert item["tablaSubcantidad"] == []
    assert item["tablaSubDescuento"] == []
    assert item["tablaSubRecargo"] == []
    assert item["tablaImpuestoAdicional"] == []
  end

  test "adds otraMoneda from currency totals when tipo_cambio is not one" do
    payload = %{
      "_id" => 31_888,
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-02-24",
      "invoice_partner_display_name" => "Cliente USD",
      "rnc_comprador" => "131-31313-1",
      "payment_reference" => "INV/2026/0888",
      "currency" => "USD",
      "tipo_cambio" => 60.0,
      "tax_totals" => %{
        "base_amount" => 60_000.0,
        "base_amount_currency" => 1000.0,
        "tax_amount" => 10_800.0,
        "tax_amount_currency" => 180.0,
        "total_amount" => 70_800.0,
        "total_amount_currency" => 1180.0,
        "subtotals" => [
          %{
            "tax_groups" => [
              %{
                "base_amount" => 60_000.0,
                "tax_amount" => 10_800.0
              }
            ]
          }
        ]
      },
      "invoice_items" => [
        %{
          "name" => "Servicio USD",
          "price_subtotal" => 60_000.0,
          "price_unit" => 60_000.0,
          "quantity" => 1.0,
          "tax_ids" => [3]
        }
      ]
    }

    company = %Company{company_name: "EDOC SRL", rnc: "123456789"}
    mapped = PayloadMapper.map_e31(payload, company, e_doc: "E310000000888")

    assert mapped["encabezado"]["totales"]["montoGravadoTotal"] == money(60_000.0)
    assert mapped["encabezado"]["totales"]["totalITBIS"] == money(10_800.0)
    assert mapped["encabezado"]["totales"]["montoTotal"] == money(70_800.0)

    assert mapped["encabezado"]["otraMoneda"] == %{
             "tipoMoneda" => "USD",
             "tipoCambio" => money(60.0),
             "montoGravadoTotalOtraMoneda" => money(1000.0),
             "montoGravado1OtraMoneda" => money(1000.0),
             "totalITBISOtraMoneda" => money(180.0),
             "totalITBIS1OtraMoneda" => money(180.0),
             "impuestosAdicionalesOtraMoneda" => [],
             "montoTotalOtraMoneda" => money(1180.0)
           }
  end

  test "maps E32 odoo payload into the target etax shape" do
    payload = %{
      "_id" => 22_287,
      "amount_tax" => 0.0,
      "amount_total" => 3000.0,
      "amount_untaxed" => 3000.0,
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-02-24",
      "invoice_origin" => false,
      "invoice_partner_display_name" => "Consumidor Final",
      "name" => "INV/2026/02/0099",
      "partner_id" => 316,
      "payment_reference" => "INV/2026/02/0099",
      "x_studio_e_doc_inv" => "E32",
      "invoice_items" => [
        %{
          "name" => "[ITEM001] Articulo Exento",
          "price_subtotal" => 3000.0,
          "price_unit" => 1000.0,
          "quantity" => 3.0,
          "tax_ids" => []
        }
      ]
    }

    company = %Company{
      company_name: "EDOC SRL",
      rnc: "123456789"
    }

    mapped = PayloadMapper.map_e32(payload, company, e_doc: "E320000000001")

    assert Enum.sort(Map.keys(mapped)) == [
             "descuentosORecargos",
             "detallesItems",
             "encabezado",
             "fechaHoraFirma",
             "paginacion",
             "subtotales"
           ]

    assert mapped["encabezado"]["version"] == "1.0"

    assert mapped["encabezado"]["idDoc"] == %{
             "tipoeCF" => 32,
             "encf" => "E320000000001",
             "tipoIngresos" => "01",
             "tipoPago" => 2,
             "tablaFormasPago" => []
           }

    assert mapped["encabezado"]["emisor"]["municipio"] == "320301"
    assert mapped["encabezado"]["emisor"]["provincia"] == "320000"

    assert mapped["encabezado"]["totales"] == %{
             "montoExento" => money(3000.0),
             "impuestosAdicionales" => [],
             "montoTotal" => money(3000.0)
           }

    assert [
             %{
               "numeroLinea" => 1,
               "indicadorFacturacion" => 4,
               "nombreItem" => "Articulo Exento",
               "unidadMedida" => "43",
               "cantidadItem" => 3.0,
               "precioUnitarioItem" => money(1000.0),
               "montoItem" => money(3000.0)
             } = item
           ] = mapped["detallesItems"]

    assert item["tablaCodigosItem"] == []
    assert item["tablaSubcantidad"] == []
    assert item["tablaSubDescuento"] == []
    assert item["tablaSubRecargo"] == []
    assert item["tablaImpuestoAdicional"] == []
  end

  test "formats currency fields with exactly two decimal places" do
    payload = %{
      "_id" => 22_288,
      "amount_tax" => 0.0,
      "amount_total" => 1.234,
      "amount_untaxed" => 1.234,
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-02-24",
      "invoice_partner_display_name" => "Consumidor Final",
      "payment_reference" => "INV/2026/02/0100",
      "x_studio_e_doc_inv" => "E32",
      "invoice_items" => [
        %{
          "name" => "Articulo Exento",
          "price_subtotal" => 1.234,
          "price_unit" => 1.2,
          "quantity" => 1.0,
          "tax_ids" => []
        }
      ]
    }

    company = %Company{company_name: "EDOC SRL", rnc: "123456789"}

    mapped = PayloadMapper.map_e32(payload, company, e_doc: "E320000000002")

    assert mapped["encabezado"]["totales"]["montoExento"] == "1.23"
    assert mapped["encabezado"]["totales"]["montoTotal"] == "1.23"

    assert [
             %{
               "precioUnitarioItem" => "1.20",
               "montoItem" => "1.23"
             }
           ] = mapped["detallesItems"]
  end

  test "maps tipoPago from invoice_payment_term_id" do
    base_payload = %{
      "_id" => 31_556,
      "amount_tax" => 180.0,
      "amount_total" => 1180.0,
      "amount_untaxed" => 1000.0,
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-02-24",
      "payment_reference" => "INV/2026/0556",
      "x_studio_e_doc_inv" => "E31",
      "invoice_items" => [
        %{
          "name" => "Item Gravado",
          "price_subtotal" => 1000.0,
          "price_unit" => 1000.0,
          "quantity" => 1.0,
          "tax_ids" => [3]
        }
      ]
    }

    company = %Company{company_name: "EDOC SRL", rnc: "123456789"}

    mapped_term_1 =
      base_payload
      |> Map.put("invoice_payment_term_id", [1, "Immediate Payment"])
      |> PayloadMapper.map_e31(company, e_doc: "E310000005560")

    mapped_other_term =
      base_payload
      |> Map.put("invoice_payment_term_id", [4, "30 Days"])
      |> PayloadMapper.map_e31(company, e_doc: "E310000005561")

    assert mapped_term_1["encabezado"]["idDoc"]["tipoPago"] == 1
    assert mapped_other_term["encabezado"]["idDoc"]["tipoPago"] == 2
  end

  test "maps indicadorFacturacion from payload tax amount for E31" do
    base_payload = %{
      "_id" => 31_555,
      "amount_total" => 1180.0,
      "amount_untaxed" => 1000.0,
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-02-24",
      "payment_reference" => "INV/2026/0555",
      "x_studio_e_doc_inv" => "E31",
      "invoice_items" => [
        %{
          "name" => "Item Gravado",
          "price_subtotal" => 1000.0,
          "price_unit" => 1000.0,
          "quantity" => 1.0,
          "tax_ids" => [3]
        }
      ]
    }

    company = %Company{company_name: "EDOC SRL", rnc: "123456789"}

    mapped_zero_tax =
      base_payload
      |> Map.put("tax_amount", 0.0)
      |> PayloadMapper.map_e31(company, e_doc: "E310000005550")

    mapped_with_tax =
      base_payload
      |> Map.put("tax_amount", 180.0)
      |> PayloadMapper.map_e31(company, e_doc: "E310000005551")

    assert [%{"indicadorFacturacion" => 4}] = mapped_zero_tax["detallesItems"]
    assert [%{"indicadorFacturacion" => 1}] = mapped_with_tax["detallesItems"]
  end

  test "sets indicadorBienoServicio from item type" do
    payload = %{
      "_id" => 32_999,
      "amount_tax" => 0.0,
      "amount_total" => 2500.0,
      "amount_untaxed" => 2500.0,
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-02-24",
      "payment_reference" => "INV/2026/0299",
      "x_studio_e_doc_inv" => "E31",
      "invoice_items" => [
        %{
          "name" => "Servicio de soporte",
          "type" => "service",
          "price_subtotal" => 1000.0,
          "price_unit" => 1000.0,
          "quantity" => 1.0,
          "tax_ids" => [3]
        },
        %{
          "name" => "Producto fisico",
          "type" => "consu",
          "price_subtotal" => 1500.0,
          "price_unit" => 1500.0,
          "quantity" => 1.0,
          "tax_ids" => [3]
        }
      ]
    }

    company = %Company{company_name: "EDOC SRL", rnc: "123456789"}
    mapped = PayloadMapper.map_e31(payload, company, e_doc: "E310000009998")

    assert [
             %{"indicadorBienoServicio" => 2},
             %{"indicadorBienoServicio" => 1}
           ] = mapped["detallesItems"]
  end

  test "maps E33 odoo payload into the target etax shape" do
    payload = %{
      "_id" => 32_287,
      "amount_tax" => 0.0,
      "amount_total" => 4000.0,
      "amount_untaxed" => 4000.0,
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-03-15",
      "invoice_origin" => false,
      "invoice_partner_display_name" => "Consumidor Final",
      "name" => "INV/2026/02/0101",
      "partner_id" => 316,
      "payment_reference" => "INV/2026/02/0101",
      "x_studio_e_doc_inv" => "E33",
      "reversed_entry_ref" => "E320000000002",
      "fecha_ncf_modificado" => "2026-02-20",
      "codigo_modificacion" => 3,
      "invoice_items" => [
        %{
          "name" => "[ITEM001] Articulo Exento",
          "price_subtotal" => 4000.0,
          "price_unit" => 1000.0,
          "quantity" => 4.0,
          "tax_ids" => []
        }
      ]
    }

    company = %Company{
      company_name: "EDOC SRL",
      rnc: "123456789"
    }

    mapped = PayloadMapper.map_e33(payload, company, e_doc: "E330000000001")

    assert mapped["encabezado"]["idDoc"] == %{
             "tipoeCF" => 33,
             "encf" => "E330000000001",
             "fechaVencimientoSecuencia" => "15-03-2026",
             "tipoIngresos" => "01",
             "tipoPago" => 2,
             "tablaFormasPago" => [%{"formaPago" => 1, "montoPago" => money(4000.0)}]
           }

    assert mapped["encabezado"]["emisor"]["municipio"] == "010100"
    assert mapped["encabezado"]["emisor"]["provincia"] == "010000"

    assert mapped["encabezado"]["totales"] == %{
             "montoExento" => money(4000.0),
             "impuestosAdicionales" => [],
             "montoTotal" => money(4000.0)
           }

    assert mapped["informacionReferencia"] == %{
             "ncfModificado" => "E320000000002",
             "fechaNCFModificado" => "20-02-2026",
             "codigoModificacion" => 3
           }

    assert [
             %{
               "indicadorFacturacion" => 4,
               "unidadMedida" => "43",
               "cantidadItem" => 4.0,
               "precioUnitarioItem" => money(1000.0),
               "montoItem" => money(4000.0)
             }
           ] = mapped["detallesItems"]
  end

  test "maps E34 odoo payload into the target etax shape" do
    payload = %{
      "_id" => 34_287,
      "amount_tax" => 180.0,
      "amount_total" => 1180.0,
      "amount_untaxed" => 1000.0,
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-02-24",
      "invoice_origin" => false,
      "invoice_partner_display_name" => "Cliente Fiscal",
      "name" => "RFD/2026/02/0001",
      "partner_id" => 999,
      "payment_reference" => "RFD/2026/02/0001",
      "ref" => "Ajuste de credito en factura original",
      "x_studio_e_doc_inv" => "E34",
      "reversed_entry_ref" => "E310000000001",
      "fecha_ncf_modificado" => "2026-02-20",
      "codigo_modificacion" => 2,
      "tax_totals" => %{
        "base_amount" => 1000.0,
        "tax_amount" => 180.0,
        "total_amount" => 1180.0,
        "subtotals" => [
          %{
            "tax_groups" => [
              %{"base_amount" => 1000.0, "tax_amount" => 180.0}
            ]
          }
        ]
      },
      "invoice_items" => [
        %{
          "name" => "[ITEM002] Articulo Gravado",
          "price_subtotal" => 1000.0,
          "price_unit" => 1000.0,
          "quantity" => 1.0,
          "tax_ids" => [3]
        }
      ]
    }

    company = %Company{
      company_name: "EDOC SRL",
      rnc: "123456789"
    }

    mapped = PayloadMapper.map_e34(payload, company, e_doc: "E340000000001")

    assert mapped["encabezado"]["idDoc"] == %{
             "tipoeCF" => 34,
             "encf" => "E340000000001",
             "indicadorNotaCredito" => "0",
             "indicadorMontoGravado" => 0,
             "tipoIngresos" => "01",
             "tipoPago" => 2,
             "tablaFormasPago" => []
           }

    assert mapped["encabezado"]["totales"] == %{
             "montoGravadoTotal" => money(1000.0),
             "montoGravadoI1" => money(1000.0),
             "itbis1" => 18,
             "totalITBIS" => money(180.0),
             "totalITBIS1" => money(180.0),
             "impuestosAdicionales" => [],
             "montoTotal" => money(1180.0)
           }

    assert mapped["informacionReferencia"] == %{
             "ncfModificado" => "E310000000001",
             "fechaNCFModificado" => "20-02-2026",
             "codigoModificacion" => 2,
             "razonModificacion" => "Ajuste de credito en factura original"
           }

    assert [
             %{
               "indicadorFacturacion" => 1,
               "unidadMedida" => "43",
               "cantidadItem" => 1.0,
               "precioUnitarioItem" => money(1000.0),
               "montoItem" => money(1000.0)
             }
           ] = mapped["detallesItems"]
  end

  test "maps E41 odoo payload into the target etax shape" do
    payload = %{
      "_id" => 41_287,
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-03-10",
      "invoice_partner_display_name" => "Proveedor Local",
      "rnc_comprador" => "131-31313-1",
      "partner_id" => 999,
      "payment_reference" => "BILL/2026/0001",
      "currency" => "USD",
      "tipo_cambio" => 60.0,
      "tax_totals" => %{
        "base_amount" => 10_000.0,
        "base_amount_currency" => 166.66,
        "tax_amount" => -1800.0,
        "tax_amount_currency" => -30.0,
        "total_amount" => 11_800.0,
        "total_amount_currency" => 196.66,
        "subtotals" => [
          %{
            "tax_groups" => [
              %{
                "base_amount" => 10_000.0,
                "base_amount_currency" => 166.66,
                "tax_amount" => -1800.0,
                "tax_amount_currency" => -30.0
              }
            ]
          }
        ]
      },
      "invoice_items" => [
        %{
          "name" => "[SERV001] Servicio de publicidad",
          "description" => "Servicio mensual de publicidad",
          "price_total" => 11_800.0,
          "price_subtotal" => 10000.0,
          "price_unit" => 10000.0,
          "quantity" => 1.0
        }
      ]
    }

    company = %Company{company_name: "EDOC SRL", rnc: "123456789"}

    mapped = PayloadMapper.map_e41(payload, company, e_doc: "E410000000001")

    assert mapped["encabezado"]["idDoc"] == %{
             "tipoeCF" => 41,
             "encf" => "E410000000001",
             "fechaVencimientoSecuencia" => "10-03-2026",
             "indicadorMontoGravado" => 0,
             "tipoPago" => 2,
             "tablaFormasPago" => [%{"formaPago" => 1, "montoPago" => money(11800.0)}]
           }

    assert mapped["encabezado"]["totales"] == %{
             "montoGravadoTotal" => money(10000.0),
             "montoGravadoI1" => money(10000.0),
             "itbis1" => 18,
             "totalITBIS" => money(1800.0),
             "totalITBIS1" => money(1800.0),
             "impuestosAdicionales" => [],
             "montoTotal" => money(11800.0),
             "valorPagar" => money(11800.0),
             "totalITBISRetenido" => money(1800.0),
             "totalISRRetencion" => money(1800.0)
           }

    assert mapped["encabezado"]["otraMoneda"] == %{
             "tipoMoneda" => "USD",
             "tipoCambio" => money(60.0),
             "montoGravadoTotalOtraMoneda" => money(166.66),
             "montoGravado1OtraMoneda" => money(166.66),
             "totalITBISOtraMoneda" => money(30.0),
             "totalITBIS1OtraMoneda" => money(30.0),
             "impuestosAdicionalesOtraMoneda" => [],
             "montoTotalOtraMoneda" => money(196.66)
           }

    assert mapped["encabezado"]["emisor"]["razonSocialEmisor"] == "Proveedor Local"
    assert mapped["encabezado"]["emisor"]["rncEmisor"] == 131_313_131
    assert mapped["encabezado"]["comprador"]["razonSocialComprador"] == "EDOC SRL"
    assert mapped["encabezado"]["comprador"]["rncComprador"] == 123_456_789

    assert [
             %{
               "indicadorFacturacion" => 1,
               "indicadorBienoServicio" => 2,
               "unidadMedida" => "43",
               "montoItem" => money(10000.0),
               "retencion" => %{
                 "indicadorAgenteRetencionoPercepcion" => 1,
                 "montoITBISRetenido" => money(1800.0),
                 "montoISRRetenido" => money(1800.0)
               }
             }
           ] = mapped["detallesItems"]
  end

  test "computes E41 montoITBISRetenido per line from price_total minus price_subtotal" do
    payload = %{
      "_id" => 41_288,
      "amount_tax" => 540.0,
      "amount_total" => 3540.0,
      "amount_untaxed" => 3000.0,
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-03-10",
      "invoice_partner_display_name" => "Proveedor Local",
      "rnc_comprador" => "131-31313-1",
      "partner_id" => 999,
      "payment_reference" => "BILL/2026/0002",
      "invoice_items" => [
        %{
          "name" => "Linea 1",
          "price_total" => 1180.0,
          "price_subtotal" => 1000.0,
          "price_unit" => 1000.0,
          "quantity" => 1.0
        },
        %{
          "name" => "Linea 2",
          "price_total" => 2360.0,
          "price_subtotal" => 2000.0,
          "price_unit" => 2000.0,
          "quantity" => 1.0
        }
      ]
    }

    company = %Company{company_name: "EDOC SRL", rnc: "123456789"}

    mapped = PayloadMapper.map_e41(payload, company, e_doc: "E410000000002")

    assert [
             %{"retencion" => %{"montoITBISRetenido" => money(180.0)}},
             %{"retencion" => %{"montoITBISRetenido" => money(360.0)}}
           ] = mapped["detallesItems"]
  end

  test "maps E43 odoo payload into the target etax shape" do
    payload = %{
      "_id" => 43_287,
      "amount_total" => 700.0,
      "amount_untaxed" => 700.0,
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-03-10",
      "invoice_partner_display_name" => "Proveedor Gastos Menores",
      "rnc_comprador" => "101-01010-1 ",
      "payment_reference" => "BILL/2026/0002",
      "invoice_items" => [
        %{
          "name" => "Peajes viaje semana I",
          "price_subtotal" => 700.0,
          "price_unit" => 100.0,
          "quantity" => 7.0
        }
      ]
    }

    company = %Company{company_name: "EDOC SRL", rnc: "123456789"}
    mapped = PayloadMapper.map_e43(payload, company, e_doc: "E430000000001")

    assert mapped["encabezado"]["idDoc"] == %{
             "tipoeCF" => 43,
             "encf" => "E430000000001",
             "fechaVencimientoSecuencia" => "10-03-2026",
             "tablaFormasPago" => []
           }

    assert mapped["encabezado"]["emisor"]["razonSocialEmisor"] == "Proveedor Gastos Menores"
    assert mapped["encabezado"]["emisor"]["rncEmisor"] == 101_010_101
    assert mapped["encabezado"]["comprador"]["razonSocialComprador"] == "EDOC SRL"
    assert mapped["encabezado"]["comprador"]["rncComprador"] == 123_456_789

    assert mapped["encabezado"]["totales"] == %{
             "montoExento" => money(700.0),
             "impuestosAdicionales" => [],
             "montoTotal" => money(700.0)
           }

    assert [
             %{
               "indicadorFacturacion" => 4,
               "indicadorBienoServicio" => 2,
               "unidadMedida" => "43",
               "cantidadItem" => 7.0,
               "montoItem" => money(700.0)
             }
           ] = mapped["detallesItems"]
  end

  test "maps E44 odoo payload into the target etax shape" do
    payload = %{
      "_id" => 44_287,
      "amount_total" => 248_292.0,
      "amount_untaxed" => 248_292.0,
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-03-10",
      "payment_reference" => "INV/2026/0044",
      "tipo_cuenta_pago" => "CT",
      "numero_cuenta_pago" => "0301678890090",
      "banco_pago" => "BANCO XDRFT",
      "descuentos_o_recargos" => [
        %{
          "numero_linea" => 1,
          "tipo_ajuste" => "D",
          "descripcion_descuentoo_recargo" => "DESCUENTO ADMINISTRATIVO",
          "tipo_valor" => "%",
          "valor_descuentoo_recargo" => 10.0,
          "monto_descuentoo_recargo" => 27_588.0,
          "indicador_facturacion_descuentoo_recargo" => 4
        }
      ],
      "invoice_items" => [
        %{
          "name" => "Combustible AWSO",
          "price_subtotal" => 4840.0,
          "price_unit" => 220.0,
          "quantity" => 22.0
        }
      ]
    }

    company = %Company{company_name: "EDOC SRL", rnc: "123456789"}
    mapped = PayloadMapper.map_e44(payload, company, e_doc: "E440000000002")

    assert mapped["encabezado"]["idDoc"]["tipoeCF"] == 44

    assert mapped["encabezado"]["idDoc"]["tablaFormasPago"] == [
             %{"formaPago" => 2, "montoPago" => money(248_292.0)}
           ]

    assert mapped["encabezado"]["idDoc"]["tipoCuentaPago"] == "CT"
    assert mapped["encabezado"]["idDoc"]["numeroCuentaPago"] == "0301678890090"
    assert mapped["encabezado"]["idDoc"]["bancoPago"] == "BANCO XDRFT"

    assert mapped["encabezado"]["totales"] == %{
             "montoExento" => money(248_292.0),
             "impuestosAdicionales" => [],
             "montoTotal" => money(248_292.0),
             "valorPagar" => money(248_292.0)
           }

    assert [
             %{
               "numeroLinea" => 1,
               "indicadorFacturacion" => 4,
               "unidadMedida" => "43"
             }
           ] = mapped["detallesItems"]

    assert mapped["descuentosORecargos"] == [
             %{
               "numeroLinea" => 1,
               "tipoAjuste" => "D",
               "descripcionDescuentooRecargo" => "DESCUENTO ADMINISTRATIVO",
               "tipoValor" => "%",
               "valorDescuentooRecargo" => money(10.0),
               "montoDescuentooRecargo" => money(27_588.0),
               "indicadorFacturacionDescuentooRecargo" => 4
             }
           ]
  end

  test "maps E45 odoo payload into the target etax shape" do
    payload = %{
      "_id" => 45_287,
      "amount_tax" => 5400.0,
      "amount_total" => 35_400.0,
      "amount_untaxed" => 30_000.0,
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-03-10",
      "payment_reference" => "INV/2026/0045",
      "invoice_items" => [
        %{
          "name" => "Servicio publicidad",
          "description" => "Prestacion de servicios de publicidad",
          "price_subtotal" => 30_000.0,
          "price_unit" => 30_000.0,
          "quantity" => 1.0
        }
      ]
    }

    company = %Company{company_name: "EDOC SRL", rnc: "123456789"}
    mapped = PayloadMapper.map_e45(payload, company, e_doc: "E450000000001")

    assert mapped["encabezado"]["idDoc"] == %{
             "tipoeCF" => 45,
             "encf" => "E450000000001",
             "fechaVencimientoSecuencia" => "10-03-2026",
             "indicadorMontoGravado" => 0,
             "tipoIngresos" => "01",
             "tipoPago" => 2,
             "tablaFormasPago" => []
           }

    assert mapped["encabezado"]["totales"] == %{
             "montoGravadoTotal" => money(30_000.0),
             "montoGravadoI1" => money(30_000.0),
             "itbis1" => 18,
             "totalITBIS" => money(5400.0),
             "totalITBIS1" => money(5400.0),
             "impuestosAdicionales" => [],
             "montoTotal" => money(35_400.0),
             "valorPagar" => money(35_400.0)
           }

    assert [
             %{
               "indicadorFacturacion" => 1,
               "indicadorBienoServicio" => 2,
               "descripcionItem" => "Prestacion de servicios de publicidad",
               "unidadMedida" => "43"
             }
           ] = mapped["detallesItems"]
  end

  test "maps E46 odoo payload into the target etax shape" do
    payload = %{
      "_id" => 46_287,
      "amount_tax" => 0.0,
      "amount_total" => 1_800_000.0,
      "amount_untaxed" => 1_800_000.0,
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-03-10",
      "payment_reference" => "INV/2026/0046",
      "fecha_limite_pago" => "2026-05-06",
      "termino_pago" => "1 mes",
      "fecha_embarque" => "2026-04-10",
      "numero_embarque" => "10010-1207-000254",
      "numero_contenedor" => "ERTY227958722",
      "peso_bruto" => 25_000.0,
      "peso_neto" => 24_878.0,
      "unidad_peso_bruto" => "21",
      "unidad_peso_neto" => "21",
      "cantidad_bulto" => 250.0,
      "unidad_bulto" => "25",
      "volumen_bulto" => 45.0,
      "unidad_volumen" => "27",
      "numero_albaran" => "56789UJILLL",
      "contacto_entrega" => "JACINTO MANON",
      "direccion_entrega" => "ZONA HAINA",
      "telefono_adicional" => "809-555-5050",
      "invoice_items" => [
        %{
          "name" => "AGUACATE CRIOLLO",
          "default_code" => "123456",
          "price_subtotal" => 1_800_000.0,
          "price_unit" => 18_000.0,
          "quantity" => 100.0
        }
      ]
    }

    company = %Company{company_name: "EDOC SRL", rnc: "123456789"}
    mapped = PayloadMapper.map_e46(payload, company, e_doc: "E460000000001")

    assert mapped["encabezado"]["idDoc"]["tipoeCF"] == 46
    assert mapped["encabezado"]["idDoc"]["tipoPago"] == 2
    assert mapped["encabezado"]["idDoc"]["fechaLimitePago"] == "06-05-2026"
    assert mapped["encabezado"]["idDoc"]["terminoPago"] == "1 mes"

    assert mapped["encabezado"]["idDoc"]["tablaFormasPago"] == [
             %{"formaPago" => 2, "montoPago" => money(1_800_000.0)}
           ]

    assert mapped["encabezado"]["transporte"] == %{"numeroAlbaran" => "56789UJILLL"}

    assert mapped["encabezado"]["informacionesAdicionales"]["numeroEmbarque"] ==
             "10010-1207-000254"

    assert mapped["encabezado"]["informacionesAdicionales"]["pesoBruto"] == 25_000.0

    assert mapped["encabezado"]["totales"] == %{
             "montoGravadoTotal" => money(1_800_000.0),
             "montoGravadoI3" => money(1_800_000.0),
             "itbis3" => 0,
             "totalITBIS" => money(0),
             "totalITBIS3" => money(0),
             "impuestosAdicionales" => [],
             "montoTotal" => money(1_800_000.0)
           }

    assert [
             %{
               "indicadorFacturacion" => 3,
               "unidadMedida" => "43",
               "tablaCodigosItem" => [%{"tipoCodigo" => "INTERNA", "codigoItem" => "123456"}]
             }
           ] = mapped["detallesItems"]
  end

  test "maps E47 odoo payload into the target etax shape" do
    payload = %{
      "_id" => 47_287,
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-03-10",
      "payment_reference" => "INV/2026/0047",
      "identificador_extranjero" => "533445888",
      "invoice_partner_display_name" => "ALEJA FERMIN SANTOS",
      "rnc_comprador" => "533-44588-8",
      "numero_cuenta_pago" => "BB00058745214789635111111111",
      "banco_pago" =>
        "BB0111111111111111111111111111111111111111111111111111111111111111111111111",
      "currency" => "USD",
      "tipo_cambio" => 60.0,
      "tax_totals" => %{
        "base_amount" => 180_000.0,
        "base_amount_currency" => 3000.0,
        "tax_amount" => -48_600.0,
        "tax_amount_currency" => -810.0,
        "total_amount" => 180_000.0,
        "total_amount_currency" => 3000.0
      },
      "invoice_items" => [
        %{
          "name" => "LICENCIA WYI",
          "price_subtotal" => 3000.0,
          "price_unit" => 3000.0,
          "quantity" => 1.0
        }
      ]
    }

    company = %Company{company_name: "EDOC SRL", rnc: "123456789"}
    mapped = PayloadMapper.map_e47(payload, company, e_doc: "E470000000001")

    assert mapped["encabezado"]["idDoc"]["tipoeCF"] == 47
    assert mapped["encabezado"]["idDoc"]["tablaFormasPago"] == []
    assert mapped["encabezado"]["idDoc"]["numeroCuentaPago"] == "BB00058745214789635111111111"

    assert mapped["encabezado"]["idDoc"]["bancoPago"] ==
             "BB0111111111111111111111111111111111111111111111111111111111111111111111111"

    assert mapped["encabezado"]["emisor"]["rncEmisor"] == 533_445_888
    assert mapped["encabezado"]["emisor"]["razonSocialEmisor"] == "ALEJA FERMIN SANTOS"

    assert mapped["encabezado"]["comprador"] == %{
             "identificadorExtranjero" => "123456789",
             "razonSocialComprador" => "EDOC SRL"
           }

    assert mapped["encabezado"]["totales"] == %{
             "montoExento" => money(180_000.0),
             "impuestosAdicionales" => [],
             "montoTotal" => money(180_000.0),
             "totalISRRetencion" => money(48_600.0)
           }

    assert mapped["encabezado"]["otraMoneda"] == %{
             "tipoMoneda" => "USD",
             "tipoCambio" => money(60.0),
             "montoExentoOtraMoneda" => money(3000.0),
             "impuestosAdicionalesOtraMoneda" => [],
             "montoTotalOtraMoneda" => money(3000.0)
           }

    assert [
             %{
               "indicadorFacturacion" => 4,
               "unidadMedida" => "43",
               "precioUnitarioItem" => money(180_000.0),
               "montoItem" => money(180_000.0),
               "retencion" => %{
                 "indicadorAgenteRetencionoPercepcion" => 1,
                 "montoISRRetenido" => money(48_600.0)
               },
               "otraMonedaDetalle" => %{
                 "precioOtraMoneda" => money(3000.0),
                 "montoItemOtraMoneda" => money(3000.0)
               }
             }
           ] = mapped["detallesItems"]

    assert mapped["subtotales"] == [
             %{
               "numeroSubTotal" => 1,
               "descripcionSubtotal" => "N/A",
               "orden" => 1,
               "subTotalExento" => money(180_000.0),
               "montoSubTotal" => money(180_000.0),
               "lineas" => 1
             }
           ]
  end

  test "maps E47 foreign-currency line values into local detail amounts" do
    payload = %{
      "_id" => 47_133,
      "invoice_date" => "2026-04-27",
      "invoice_date_due" => "2026-04-27",
      "invoice_partner_display_name" => "Carlos Felipe Castano Velez",
      "identificador_extranjero" => "75082948",
      "currency" => "USD",
      "tipo_cambio" => 59.24,
      "tax_totals" => %{
        "base_amount" => 51_835.0,
        "base_amount_currency" => 875.0,
        "tax_amount" => -13_995.45,
        "tax_amount_currency" => -236.25,
        "total_amount" => 37_839.55,
        "total_amount_currency" => 638.75
      },
      "invoice_items" => [
        %{
          "name" => "Servicio de Consultoria\nHCM (Macrotech)",
          "price_subtotal" => 875.0,
          "price_unit" => 25.0,
          "quantity" => 35.0
        }
      ]
    }

    company = %Company{company_name: "FLOVELZ SRL", rnc: "132190068"}
    mapped = PayloadMapper.map_e47(payload, company, e_doc: "E470000000133")

    assert mapped["encabezado"]["totales"] == %{
             "montoExento" => money(51_835.0),
             "impuestosAdicionales" => [],
             "montoTotal" => money(37_839.55),
             "totalISRRetencion" => money(13_995.45)
           }

    assert mapped["encabezado"]["otraMoneda"] == %{
             "tipoMoneda" => "USD",
             "tipoCambio" => money(59.24),
             "montoExentoOtraMoneda" => money(875.0),
             "impuestosAdicionalesOtraMoneda" => [],
             "montoTotalOtraMoneda" => money(638.75)
           }

    assert [
             %{
               "precioUnitarioItem" => money(1481.0),
               "montoItem" => money(51_835.0),
               "retencion" => %{
                 "montoISRRetenido" => money(13_995.45)
               },
               "otraMonedaDetalle" => %{
                 "precioOtraMoneda" => money(25.0),
                 "montoItemOtraMoneda" => money(875.0)
               }
             }
           ] = mapped["detallesItems"]

    assert mapped["subtotales"] == [
             %{
               "numeroSubTotal" => 1,
               "descripcionSubtotal" => "N/A",
               "orden" => 1,
               "subTotalExento" => money(51_835.0),
               "montoSubTotal" => money(37_839.55),
               "lineas" => 1
             }
           ]
  end

  test "prefers explicit comprador enrichment fields when mapping E31" do
    payload = %{
      "_id" => 31_999,
      "amount_tax" => 180.0,
      "amount_total" => 1180.0,
      "amount_untaxed" => 1000.0,
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-02-24",
      "payment_reference" => "INV/2026/0999",
      "x_studio_e_doc_inv" => "E31",
      "rncComprador" => "130-98765-4",
      "razonSocialComprador" => "Cliente Enriquecido SRL",
      "direccionComprador" => "Distrito Nacional",
      "tablaTelefonoComprador" => ["809-555-9999"],
      "invoice_items" => [
        %{
          "name" => "Item",
          "price_subtotal" => 1000.0,
          "price_unit" => 1000.0,
          "quantity" => 1.0,
          "tax_ids" => [3]
        }
      ]
    }

    company = %Company{company_name: "EDOC SRL", rnc: "123456789"}
    mapped = PayloadMapper.map_e31(payload, company, e_doc: "E310000009999")

    assert mapped["encabezado"]["comprador"]["rncComprador"] == 130_987_654
    assert mapped["encabezado"]["comprador"]["razonSocialComprador"] == "Cliente Enriquecido SRL"
    assert mapped["encabezado"]["comprador"]["direccionComprador"] == "Distrito Nacional"
    assert mapped["encabezado"]["comprador"]["tablaTelefonoComprador"] == ["809-555-9999"]
  end

  test "prefers explicit emisor enrichment fields when mapping E47" do
    payload = %{
      "_id" => 47_999,
      "amount_tax" => 0.0,
      "amount_total" => 12_000.0,
      "amount_untaxed" => 12_000.0,
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-03-10",
      "identificador_extranjero" => "FOREIGN-01",
      "invoice_partner_display_name" => "Comprador Extranjero",
      "x_studio_e_doc_bill" => "E47",
      "rncEmisor" => "131-31313-1 ",
      "razonSocialEmisor" => "Proveedor E47 SRL",
      "nombreComercial" => "Proveedor E47",
      "direccionEmisor" => "Santiago, Calle 1",
      "tablaTelefonoEmisor" => ["809-444-1212"],
      "invoice_items" => [
        %{
          "name" => "Servicio",
          "price_subtotal" => 12_000.0,
          "price_unit" => 12_000.0,
          "quantity" => 1.0
        }
      ]
    }

    company = %Company{company_name: "EDOC Company", rnc: "999999999"}
    mapped = PayloadMapper.map_e47(payload, company, e_doc: "E470000009999")

    assert mapped["encabezado"]["emisor"]["rncEmisor"] == 131_313_131
    assert mapped["encabezado"]["emisor"]["razonSocialEmisor"] == "Proveedor E47 SRL"
    assert mapped["encabezado"]["emisor"]["nombreComercial"] == "Proveedor E47"
    assert mapped["encabezado"]["emisor"]["direccionEmisor"] == "Santiago, Calle 1"
    assert mapped["encabezado"]["emisor"]["tablaTelefonoEmisor"] == ["809-444-1212"]
    assert mapped["encabezado"]["comprador"]["identificadorExtranjero"] == "999999999"
    assert mapped["encabezado"]["comprador"]["razonSocialComprador"] == "EDOC Company"
  end

  test "normalizes vat buyer values across formats when mapping E31" do
    base_payload = %{
      "_id" => 31_777,
      "amount_tax" => 180.0,
      "amount_total" => 1180.0,
      "amount_untaxed" => 1000.0,
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-02-24",
      "payment_reference" => "INV/2026/1777",
      "invoice_partner_display_name" => "Cliente VAT",
      "x_studio_e_doc_inv" => "E31",
      "invoice_items" => [
        %{
          "name" => "Item VAT",
          "price_subtotal" => 1000.0,
          "price_unit" => 1000.0,
          "quantity" => 1.0,
          "tax_ids" => [3]
        }
      ]
    }

    company = %Company{company_name: "EDOC SRL", rnc: "123456789"}

    vat_formats = [
      "131244343",
      "1-31-244343",
      "13124-4343",
      " 131.24/4343 "
    ]

    for vat <- vat_formats do
      payload = Map.put(base_payload, "vat", vat)
      mapped = PayloadMapper.map_e31(payload, company, e_doc: "E310000001777")

      assert mapped["encabezado"]["comprador"]["rncComprador"] == 131_244_343
    end
  end
end