defmodule Edoc.TestSupport.CompanyOnboardingStub do
  alias Edoc.DgiiRncScraper.Result

  def lookup(rnc) do
    case config(:dgii_lookup_result) do
      nil ->
        {:ok,
         %Result{
           tax_id: rnc,
           legal_name: "Stubbed Company SRL",
           economic_activity: "SOFTWARE SERVICES",
           local_administration: "ADM LOCAL CENTRAL"
         }}

      result ->
        result
    end
  end

  def validate_odoo(_attrs) do
    config(:odoo_validation_result) || {:ok, %{message: "Odoo connection validated."}}
  end

  def validate_provider(_attrs) do
    config(:provider_validation_result) || {:ok, %{message: "Provider connection validated."}}
  end

  defp config(key) do
    Application.get_env(:edoc, :company_onboarding_test_results, %{})
    |> Map.get(key)
  end
end
