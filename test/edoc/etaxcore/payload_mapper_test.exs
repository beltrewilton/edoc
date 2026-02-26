defmodule Edoc.Etaxcore.PayloadMapperTest do
  use ExUnit.Case, async: true

  alias Edoc.Accounts.Company
  alias Edoc.Etaxcore.PayloadMapper

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

    mapped = PayloadMapper.map_invoice(payload, company, e_doc: "E310000000001", doc_type: "INV")

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
    assert mapped["encabezado"]["idDoc"]["tipoPago"] == 1
    assert mapped["encabezado"]["idDoc"]["tablaFormasPago"] == [%{"formaPago" => 1, "montoPago" => 3009.0}]

    assert mapped["encabezado"]["emisor"]["rncEmisor"] == "123456789"
    assert mapped["encabezado"]["emisor"]["razonSocialEmisor"] == "EDOC SRL"
    assert mapped["encabezado"]["emisor"]["numeroFacturaInterna"] == "INV/2026/02/0008"

    assert mapped["encabezado"]["comprador"]["razonSocialComprador"] ==
             "Santo Domingo Motors Company"

    assert mapped["encabezado"]["comprador"]["codigoInternoComprador"] == "316"
    assert mapped["encabezado"]["informacionesAdicionales"]["numeroReferencia"] == 11_287

    assert mapped["encabezado"]["totales"] == %{
             "montoGravadoTotal" => 2550.0,
             "montoGravadoI1" => 2550.0,
             "itbis1" => 18,
             "totalITBIS" => 459.0,
             "totalITBIS1" => 459.0,
             "impuestosAdicionales" => [],
             "montoTotal" => 3009.0
           }

    assert [
             %{
               "numeroLinea" => 1,
               "indicadorFacturacion" => 1,
               "nombreItem" => "Botas de Trabajo de Almacen Trugard",
               "unidadMedida" => "31",
               "cantidadItem" => 1.0,
               "precioUnitarioItem" => 2550.0,
               "montoItem" => 2550.0
             } = item
           ] = mapped["detallesItems"]

    assert item["tablaCodigosItem"] == []
    assert item["tablaSubcantidad"] == []
    assert item["tablaSubDescuento"] == []
    assert item["tablaSubRecargo"] == []
    assert item["tablaImpuestoAdicional"] == []
  end
end
