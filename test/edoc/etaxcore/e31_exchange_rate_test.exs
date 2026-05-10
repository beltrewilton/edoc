defmodule Edoc.Etaxcore.E31ExchangeRateTest do
  use ExUnit.Case, async: true

  alias Edoc.Accounts.Company
  alias Edoc.Etaxcore.E31Pipeline

  @company %Company{company_name: "EDOC SRL", rnc: "123456789"}

  test "computes tipoCambio from tax totals and keeps tax indicator for foreign taxed items" do
    payload = %{
      "_id" => 31_777,
      "amount_total" => 20.0,
      "amount_untaxed" => 20.0,
      "amount_tax" => 0.0,
      "currency" => "USD",
      "invoice_date" => "2026-02-24",
      "invoice_date_due" => "2026-02-24",
      "payment_reference" => "INV/2026/0777",
      "tipo_cambio" => 99.0,
      "tax_totals" => %{
        "base_amount" => 1000.0,
        "base_amount_currency" => 20.0,
        "tax_amount" => 180.0,
        "tax_amount_currency" => 3.6,
        "total_amount" => 1180.0,
        "total_amount_currency" => 20.0,
        "subtotals" => [
          %{
            "tax_groups" => [
              %{
                "base_amount" => 1000.0,
                "base_amount_currency" => 20.0,
                "tax_amount" => 180.0,
                "tax_amount_currency" => 3.6,
                "involved_tax_ids" => [1]
              }
            ]
          }
        ]
      },
      "invoice_items" => [
        %{
          "name" => "Foreign taxed service",
          "price_subtotal" => 20.0,
          "price_unit" => 20.0,
          "quantity" => 1.0,
          "tax_ids" => [1],
          "type" => "service"
        }
      ]
    }

    mapped = E31Pipeline.map(payload, @company, e_doc: "E310000007777")

    assert mapped["encabezado"]["otraMoneda"]["tipoCambio"] == "59.00"
    assert [%{"indicadorFacturacion" => 1}] = mapped["detallesItems"]
  end
end
