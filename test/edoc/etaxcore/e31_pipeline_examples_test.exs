defmodule Edoc.Etaxcore.E31PipelineExamplesTest do
  use ExUnit.Case, async: true

  alias Edoc.Accounts.Company
  alias Edoc.Etaxcore.E31Pipeline

  @company %Company{company_name: "FLOVELZ SRL", rnc: "132190068"}
  @examples ~w(E31001 E31002 E31003)

  describe "provided E31 JSON examples" do
    for stem <- @examples do
      @stem stem

      test "#{stem}-Odoo.json maps to #{stem}.json" do
        input = load_input(@stem)
        expected = load_expected(@stem)
        edoc = expected["encabezado"]["idDoc"]["encf"]
        fecha_hora_firma = expected["fechaHoraFirma"]

        actual =
          E31Pipeline.map(input, @company,
            e_doc: edoc,
            fecha_hora_firma: fecha_hora_firma
          )

        assert actual == expected
      end
    end
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
    Path.expand("../../../notes/E31/#{stem}#{suffix}", __DIR__)
  end

  defp strip_json_comments(json) do
    Regex.replace(~r{//.*$}m, json, "")
  end
end
