defmodule Edoc.Etaxcore.E32PipelineExamplesTest do
  use ExUnit.Case, async: true

  alias Edoc.Accounts.Company
  alias Edoc.Etaxcore.E32Pipeline

  @company %Company{company_name: "FLOVELZ SRL", rnc: "132190068"}

  test "E32001-Odoo.json maps to E32001.json" do
    input = load_input("E32001")
    expected = load_expected("E32001")
    edoc = expected["encabezado"]["idDoc"]["encf"]
    fecha_hora_firma = expected["fechaHoraFirma"]

    actual =
      E32Pipeline.map(input, @company,
        e_doc: edoc,
        fecha_hora_firma: fecha_hora_firma
      )

    assert actual == expected
  end

  test "does not add otraMoneda when tax totals ratio is one" do
    input =
      "E32001"
      |> load_input()
      |> local_currency_payload()

    actual =
      E32Pipeline.map(input, @company,
        e_doc: "E320000000999",
        fecha_hora_firma: "27-04-2026 20:45:56"
      )

    refute Map.has_key?(actual["encabezado"], "otraMoneda")
    assert actual["encabezado"]["idDoc"]["tablaFormasPago"] == [
             %{"formaPago" => 2, "montoPago" => "2000.00"}
           ]

    assert [%{"montoItem" => "2000.00", "precioUnitarioItem" => "2000.00"}] =
             actual["detallesItems"]
  end

  defp load_input(stem) do
    stem
    |> example_path("-Odoo.json")
    |> File.read!()
    |> Jason.decode!()
  end

  defp load_expected(stem) do
    stem
    |> example_path(".json")
    |> File.read!()
    |> strip_json_comments()
    |> Jason.decode!()
  end

  defp example_path(stem, suffix) do
    Path.expand("../../../notes/E32/#{stem}#{suffix}", __DIR__)
  end

  defp strip_json_comments(json) do
    Regex.replace(~r{//.*$}m, json, "")
  end

  defp local_currency_payload(payload) do
    payload
    |> put_in(["tax_totals", "base_amount"], 2000)
    |> put_in(["tax_totals", "base_amount_currency"], 2000)
    |> put_in(["tax_totals", "total_amount"], 2000)
    |> put_in(["tax_totals", "total_amount_currency"], 2000)
    |> put_in(["tax_totals", "subtotals", Access.at(0), "base_amount"], 2000)
    |> put_in(["tax_totals", "subtotals", Access.at(0), "base_amount_currency"], 2000)
    |> put_in(["tax_totals", "subtotals", Access.at(0), "tax_groups", Access.at(0), "base_amount"], 2000)
    |> put_in(
      ["tax_totals", "subtotals", Access.at(0), "tax_groups", Access.at(0), "base_amount_currency"],
      2000
    )
    |> put_in(
      [
        "tax_totals",
        "subtotals",
        Access.at(0),
        "tax_groups",
        Access.at(0),
        "display_base_amount"
      ],
      2000
    )
    |> put_in(
      [
        "tax_totals",
        "subtotals",
        Access.at(0),
        "tax_groups",
        Access.at(0),
        "display_base_amount_currency"
      ],
      2000
    )
  end
end
