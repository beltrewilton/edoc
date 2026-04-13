defmodule Edoc.CompanyOnboarding.ProviderValidation do
  @moduledoc """
  Connectivity validation for provider credentials collected during company onboarding.
  """

  alias Edoc.Accounts.Company

  @probe_payload %{
    "probe" => true,
    "source" => "edoc_company_onboarding"
  }

  @spec validate_provider(map() | Company.t()) :: {:ok, map()} | {:error, String.t()}
  def validate_provider(%Company{} = company) do
    endpoint = present_string(company.provider_endpoint)
    api_key = present_string(company.provider_apikey)

    req =
      Req.new(
        method: :post,
        url: endpoint,
        headers: [
          {"content-type", "application/json"},
          {"accept", "application/json"},
          {"api-key", api_key}
        ],
        json: @probe_payload,
        receive_timeout: 15_000
      )

    case Req.request(req) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        {:ok, %{message: "Provider connection validated.", status: status}}

      {:ok, %Req.Response{status: status}} when status in [400, 405, 415, 422] ->
        {:ok,
         %{
           message: "Provider endpoint reached. The probe payload was rejected, but connectivity is valid.",
           status: status
         }}

      {:ok, %Req.Response{status: 401}} ->
        {:error, "Provider rejected the API key (401 Unauthorized)."}

      {:ok, %Req.Response{status: 403}} ->
        {:error, "Provider rejected the API key (403 Forbidden)."}

      {:ok, %Req.Response{status: 404}} ->
        {:error, "Provider endpoint was not found (404). Check the URL."}

      {:ok, %Req.Response{status: status}} when status >= 500 ->
        {:error, "Provider responded with #{status}. Retry when the service is available."}

      {:ok, %Req.Response{status: status}} ->
        {:error, "Provider validation failed with HTTP #{status}."}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  def validate_provider(attrs) when is_map(attrs) do
    attrs
    |> company_from_attrs()
    |> validate_provider()
  end

  defp company_from_attrs(attrs) do
    %Company{
      provider_endpoint: fetch_value(attrs, "provider_endpoint"),
      provider_apikey: fetch_value(attrs, "provider_apikey")
    }
  end

  defp fetch_value(attrs, key) when is_binary(key) do
    Map.get(attrs, key) || Map.get(attrs, String.to_existing_atom(key))
  end

  defp present_string(value) when is_binary(value), do: String.trim(value)
  defp present_string(_value), do: ""
end
