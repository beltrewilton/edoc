defmodule Edoc.EtaxcoreClient do
  @moduledoc """
  Thin eTaxCore HTTP client.

  * Sends a JSON payload to the configured eTaxCore endpoint.
  * Returns the decoded JSON response as a map.
test9-flovelz.
  Environment variables:

    * `ETAXCORE_ENDPOINT` – full URL of the eTaxCore endpoint
    * `ETAXCORE_API_KEY`  – API key sent as the `api-key` header

  This module **does not** validate request or response shapes.
  You are responsible for building a valid payload and interpreting
  the response.
  """

  require Logger

  @type request_body :: map()
  @type response_body :: map()

  @doc """
  Sends the given `payload` (a map) as JSON to eTaxCore.

  Returns:

    * `{:ok, response_body}`  on HTTP 2xx
    * `{:error, {:http_error, status, body}}` on non-2xx
    * `{:error, exception}`   on transport error
  """
  @spec send_invoice(request_body()) ::
          {:ok, response_body()} | {:error, term()}
  def send_invoice(payload) when is_map(payload) do
    post(payload)
  end

  @doc """
  Same as `send_invoice/1` but raises on error.
  """
  @spec send_invoice!(request_body()) :: response_body()
  def send_invoice!(payload) when is_map(payload) do
    case send_invoice(payload) do
      {:ok, resp} ->
        resp

      {:error, {:http_error, status, body}} ->
        raise "eTaxCore HTTP error (status #{status}): #{inspect(body)}"

      {:error, exception} ->
        raise "eTaxCore request failed: #{inspect(exception)}"
    end
  end

  ## Internal HTTP call

  defp post(payload) when is_map(payload) do
    url = System.fetch_env!("ETAXCORE_ENDPOINT")
    api_key = System.fetch_env!("ETAXCORE_API_KEY")

    req =
      Req.new(
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
