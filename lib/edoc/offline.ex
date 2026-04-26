defmodule OfflinePayload do
  alias Edoc.Accounts.Company
  alias Edoc.Etaxcore.PayloadJson
  alias Edoc.Etaxcore.PayloadMapper

  @company %Company{
    id: "a1fde0a1-4cbe-433d-b9e4-3ec654338a14",
    company_name: "FLOVELZ SRL",
    rnc: "132190068"
  }

  @cases %{
    "41" =>
      {&PayloadMapper.map_e41/3,
       [e_doc: "E410000000101", fecha_hora_firma: "14-04-2026 00:33:31"]},
    "43" =>
      {&PayloadMapper.map_e43/3,
       [e_doc: "E430000000102", fecha_hora_firma: "16-04-2026 02:21:50"]},
    "47" =>
      {&PayloadMapper.map_e47/3,
       [e_doc: "E470000000101", fecha_hora_firma: "14-04-2026 00:44:41"]}
  }

  def generate(case_id) do
    {mapper, opts} = Map.fetch!(@cases, case_id)

    payload =
      "tofix/#{case_id}_odoo.json"
      |> File.read!()
      |> Jason.decode!()
      |> mapper.(@company, opts)

    File.mkdir_p!("tofix/generated")

    path = "tofix/generated/#{case_id}_generated.json"
    File.write!(path, PayloadJson.encode!(payload, pretty: true))

    {:ok, path}
  end

  def generate_all do
    @cases
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map(&generate/1)
  end

  def matches_expected?(case_id) do
    {mapper, opts} = Map.fetch!(@cases, case_id)

    actual =
      "tofix/#{case_id}_odoo.json"
      |> File.read!()
      |> Jason.decode!()
      |> mapper.(@company, opts)

    expected =
      "tofix/#{case_id}_expected.json"
      |> File.read!()
      |> String.replace(~r/\s*\/\/.*$/m, "")
      |> Jason.decode!()

    actual == expected
  end

  def compare_all do
    @cases
    |> Map.keys()
    |> Enum.sort()
    |> Map.new(fn case_id -> {case_id, matches_expected?(case_id)} end)
  end
end