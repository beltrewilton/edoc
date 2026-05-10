defmodule Edoc.Etaxcore.PayloadMapperSequenceTest do
  use ExUnit.Case, async: true

  alias Edoc.Accounts.Company
  alias Edoc.Etaxcore.PayloadMapper

  @company %Company{company_name: "FLOVELZ SRL", rnc: "132190068"}

  test "map_invoice requires the generated e_doc sequence" do
    assert_raise ArgumentError, "missing generated e_doc for encf", fn ->
      PayloadMapper.map_invoice(%{"x_studio_e_doc_inv" => "E31"}, @company)
    end
  end

  test "map_invoice dispatches from generated e_doc instead of Odoo e-CF hints" do
    payload =
      "notes/E31/E31001-Odoo.json"
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("x_studio_e_doc_inv", "E32")

    mapped = PayloadMapper.map_invoice(payload, @company, e_doc: "E310000009999")

    assert mapped["encabezado"]["idDoc"]["tipoeCF"] == 31
    assert mapped["encabezado"]["idDoc"]["encf"] == "E310000009999"
  end
end
