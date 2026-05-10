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
end
