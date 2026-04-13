defmodule Edoc.EtaxcoreClient do
  @moduledoc """
  Thin eTaxCore HTTP client.

  Sends a JSON payload to the provider endpoint configured for a company and
  returns the decoded JSON response as a map.

  This module does not validate request or response shapes. Callers are
  responsible for building valid payloads and interpreting the response.
  """

  alias Edoc.Accounts.Company

  require Logger

  @type request_body :: map()
  @type response_body :: map()

  @doc """
  Sends the given `payload` (a map) as JSON to the company's configured
  provider endpoint.

  Returns:

    * `{:ok, response_body}` on HTTP 2xx
    * `{:error, {:http_error, status, body}}` on non-2xx
    * `{:error, {:missing_provider_config, field}}` when the company is missing
      provider credentials
    * `{:error, exception}` on transport error
  """
  @spec send_invoice(request_body(), Company.t()) ::
          {:ok, response_body()} | {:error, term()}
  def send_invoice(payload, %Company{} = company) when is_map(payload) do
    post(payload, company)
  end

  @doc """
  Same as `send_invoice/2` but raises on error.
  """
  @spec send_invoice!(request_body(), Company.t()) :: response_body()
  def send_invoice!(payload, %Company{} = company) when is_map(payload) do
    case send_invoice(payload, company) do
      {:ok, resp} ->
        resp

      {:error, {:http_error, status, body}} ->
        raise "eTaxCore HTTP error (status #{status}): #{inspect(body)}"

      {:error, {:missing_provider_config, field}} ->
        raise "eTaxCore provider configuration missing: #{field}"

      {:error, exception} ->
        raise "eTaxCore request failed: #{inspect(exception)}"
    end
  end

  defp post(payload, %Company{} = company) when is_map(payload) do
    with {:ok, url} <- fetch_provider_value(company, :provider_endpoint),
         {:ok, api_key} <- fetch_provider_value(company, :provider_apikey) do
      req =
        Req.new(
          method: :post,
          url: url,
          headers: [
            {"content-type", "application/json"},
            {"accept", "application/json"},
            {"api-key", api_key}
          ],
          json: payload
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
          {:ok, body}

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.warning("eTaxCore non-2xx response (#{status}): #{inspect(body)}")
          {:error, {:http_error, status, body}}

        {:error, exception} ->
          Logger.error("eTaxCore HTTP error: #{inspect(exception)}")
          {:error, exception}
      end
    end
  end

  defp fetch_provider_value(%Company{} = company, field) do
    case Map.get(company, field) do
      value when is_binary(value) ->
        trimmed_value = String.trim(value)

        if byte_size(trimmed_value) > 0 do
          {:ok, trimmed_value}
        else
          {:error, {:missing_provider_config, field}}
        end

      _ ->
        {:error, {:missing_provider_config, field}}
    end
  end
end
