defmodule Edoc.Etaxcore.E41PipelineTest do
  use ExUnit.Case, async: true

  alias Edoc.Accounts.Company
  alias Edoc.Etaxcore.E41Pipeline

  test "maps E41 using the old retention behavior contract" do
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
        "total_amount_currency" => 196.66
      },
      "invoice_items" => [
        %{
          "name" => "[SERV001] Servicio de publicidad",
          "price_total" => 11_800.0,
          "price_subtotal" => 10_000.0,
          "price_unit" => 10_000.0,
          "quantity" => 1.0
        }
      ]
    }

    company = %Company{company_name: "EDOC SRL", rnc: "123456789"}

    assert %{
             "encabezado" => %{
               "idDoc" => %{
                 "tipoeCF" => 41,
                 "FechaLimitePago" => "17-03-2026"
               },
               "totales" => %{
                 "montoExento" => "11800.00",
                 "montoTotal" => "11800.00",
                 "totalISRRetencion" => "1800.00"
               },
               "otraMoneda" => %{
                 "montoExentoOtraMoneda" => "196.66",
                 "montoTotalOtraMoneda" => "196.66"
               }
             },
             "detallesItems" => [
               %{
                 "indicadorFacturacion" => 4,
                 "retencion" => %{"montoISRRetenido" => "1800.00"},
                 "montoItem" => "10000.00",
                 "otraMonedaDetalle" => %{
                   "precioOtraMoneda" => "10000.00",
                   "montoItemOtraMoneda" => "10000.00"
                 }
               }
             ]
           } = E41Pipeline.map(payload, company, e_doc: "E410000000001")
  end
end
