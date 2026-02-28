defmodule Edoc.Etaxcore.InvoiceService do
  @moduledoc """
  Orchestrates eTaxCore invoice delivery and persistence.
  """

  alias Edoc.Accounts
  alias Edoc.Accounts.Company
  alias Edoc.Etaxcore.PayloadMapper
  alias Edoc.EtaxcoreClient
  alias Edoc.OdooAutomationClient, as: Odoo
  alias Edoc.Repo
  alias Edoc.RequestLogger
  alias Edoc.Transaction
  require Logger

  @type odoo_context :: {Odoo.t(), integer()} | nil

  @type success_result :: %{
          transaction: Transaction.t(),
          provider_response: map()
        }

  @type error_result :: %{
          optional(:transaction) => Transaction.t(),
          provider_response: map()
        }

  @spec send_invoice(map(), Company.t(), keyword()) ::
          {:ok, success_result()} | {:error, error_result() | Ecto.Changeset.t() | term()}
  def send_invoice(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    tenant = Keyword.fetch!(opts, :tenant)
    request_context = Keyword.get(opts, :request_context, %{})
    odoo_context = Keyword.get(opts, :odoo_context)

    with :ok <- log_request(request_context, payload),
         {:ok, e_doc, doc_type} <- generate_edoc(payload),
         {:ok, request_payload} <- build_request_payload(payload, company, e_doc),
         {:ok, transaction} <-
           insert_transaction(company, tenant, payload, request_payload, e_doc),
         {:ok, result} <-
           dispatch_request(
             transaction,
             tenant,
             request_payload,
             payload,
             odoo_context,
             e_doc,
             doc_type
           ) do
      {:ok, result}
    end
  end

  defp log_request(%{} = request_context, payload) do
    payload
    |> build_log_entry(request_context)
    |> RequestLogger.append()
  rescue
    exception -> {:error, {:request_log_error, exception}}
  end

  defp build_log_entry(payload, context) do
    headers = Map.get(context, :headers, [])

    headers_map =
      headers
      |> Map.new(fn {key, value} -> {"header_" <> to_string(key), value} end)

    base_entry = %{
      ts: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      ip: format_ip(Map.get(context, :remote_ip)),
      method: Map.get(context, :method),
      path: Map.get(context, :path),
      headers: Map.new(headers),
      body: payload
    }

    Map.merge(base_entry, headers_map)
  end

  defp build_request_payload(payload, %Company{} = company, e_doc) do
    {:ok, PayloadMapper.map_invoice(payload, company, e_doc: e_doc)}
  end

  defp dispatch_request(
         %Transaction{} = transaction,
         _tenant,
         request_payload,
         payload,
         odoo_context,
         e_doc,
         doc_type
       ) do
    _request_at = DateTime.utc_now(:second)

    print_json("request_payload", request_payload)
    print_json("payload", payload)

    maybe_run_odoo_invoice_actions(odoo_context, payload, e_doc, doc_type)

    # provider_result =
    #   case maybe_run_odoo_invoice_actions(odoo_context, payload, e_doc, doc_type) do
    #     :ok -> safe_send_invoice(request_payload)
    #     {:error, reason} -> {:error, {:odoo_invoice_action_error, reason}}
    #   end

    # normalized_provider_response = normalize_provider_response(provider_result)

    {:ok,
     %{
       transaction: transaction,
       provider_response: %{}
     }}

    # case persist_provider_exchange(
    #        transaction,
    #        tenant,
    #        request_payload,
    #        request_at,
    #        normalized_provider_response
    #      ) do
    #   :ok ->
    #     case provider_result do
    #       {:ok, _body} ->
    #         {:ok,
    #          %{
    #            transaction: transaction,
    #            provider_response: normalized_provider_response
    #          }}

    #       {:error, _reason} ->
    #         {:error,
    #          %{
    #            transaction: transaction,
    #            provider_response: normalized_provider_response
    #          }}
    #     end

    #   {:error, changeset} ->
    #     {:error, changeset}
    # end
  end

  defp maybe_run_odoo_invoice_actions(odoo_context, payload, e_doc, doc_type) do
    case payload_invoice_id(payload) do
      nil ->
        :ok

      invoice_id ->
        do_run_odoo_invoice_actions(odoo_context, invoice_id, e_doc, doc_type)
    end
  end

  defp do_run_odoo_invoice_actions({%Odoo{} = client, uid}, invoice_id, e_doc, doc_type) do
    try do
      maybe_add_invoice_sequence(client, uid, invoice_id, e_doc, doc_type)
      Odoo.add_invoice_log_note(client, uid, invoice_id, accepted_request_note())
      :ok
    rescue
      exception ->
        Logger.error("Failed to run Odoo invoice actions: #{Exception.message(exception)}")
        {:error, exception}
    end
  end

  defp do_run_odoo_invoice_actions(nil, invoice_id, _e_doc, _doc_type) do
    Logger.warning(
      "Skipping Odoo invoice actions due to missing Odoo context for invoice #{inspect(invoice_id)}"
    )

    :ok
  end

  defp do_run_odoo_invoice_actions(_other, invoice_id, _e_doc, _doc_type) do
    Logger.warning(
      "Skipping Odoo invoice actions due to invalid Odoo context for invoice #{inspect(invoice_id)}"
    )

    :ok
  end

  defp maybe_add_invoice_sequence(_client, _uid, _invoice_id, e_doc, doc_type)
       when is_nil(e_doc) or is_nil(doc_type),
       do: :ok

  defp maybe_add_invoice_sequence(%Odoo{} = client, uid, invoice_id, e_doc, doc_type) do
    Odoo.add_invoice_sequence(client, uid, invoice_id, e_doc, doc_type)
  end

  defp accepted_request_note do
    "REQUEST ACEPTADO EN PLATAFORMA #{Date.utc_today()}"
  end

  defp safe_send_invoice(payload) do
    EtaxcoreClient.send_invoice(payload)
  rescue
    exception ->
      Logger.error("eTaxCore request failed with exception: #{Exception.message(exception)}")
      {:error, {:client_exception, exception}}
  end

  defp insert_transaction(
         %Company{id: company_id},
         tenant,
         payload,
         request_payload,
         e_doc \\ nil
       ) do
    attrs = %{
      company_id: company_id,
      odoo_request: payload,
      provider_request: request_payload,
      odoo_request_at: DateTime.utc_now(:second),
      provider_request_at: DateTime.utc_now(:second),
      edoc: e_doc
    }

    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Repo.insert(prefix: tenant)
  end

  defp persist_provider_exchange(
         %Transaction{} = transaction,
         tenant,
         request_payload,
         request_at,
         normalized_provider_response
       ) do
    attrs = %{
      provider_request: request_payload,
      provider_request_at: request_at,
      provider_response: normalized_provider_response,
      provider_response_at: DateTime.utc_now(:second)
    }

    transaction
    |> Transaction.changeset(attrs)
    |> Repo.update(prefix: tenant)
    |> case do
      {:ok, _transaction} ->
        :ok

      {:error, changeset} ->
        Logger.error(
          "Failed to persist provider exchange for transaction #{transaction.id}: #{inspect(changeset.errors)}"
        )

        {:error, changeset}
    end
  end

  defp normalize_provider_response({:ok, body}) do
    %{
      "status" => "ok",
      "body" => body
    }
  end

  defp normalize_provider_response({:error, {:http_error, status, body}}) do
    %{
      "status" => "error",
      "type" => "http_error",
      "status_code" => status,
      "body" => body
    }
  end

  defp normalize_provider_response({:error, {:odoo_invoice_action_error, reason}}) do
    %{
      "status" => "error",
      "type" => "odoo_invoice_action_error",
      "reason" => format_reason(reason)
    }
  end

  defp normalize_provider_response({:error, {:client_exception, exception}}) do
    %{
      "status" => "error",
      "type" => "client_exception",
      "reason" => Exception.message(exception)
    }
  end

  defp normalize_provider_response({:error, reason}) do
    %{
      "status" => "error",
      "type" => "transport_error",
      "reason" => format_reason(reason)
    }
  end

  defp print_json(label, value) do
    output =
      case Jason.encode(value, pretty: true) do
        {:ok, json} -> json
        {:error, _reason} -> inspect(value, pretty: true, limit: :infinity)
      end

    IO.puts("#{label}:")
    IO.puts(output)
  end

  defp format_reason(%_{__exception__: true} = exception), do: Exception.message(exception)
  defp format_reason(reason), do: inspect(reason)

  defp payload_invoice_id(payload) do
    payload
    |> payload_value("_id")
    |> normalize_invoice_id()
    |> case do
      nil -> payload |> payload_value("id") |> normalize_invoice_id()
      invoice_id -> invoice_id
    end
  end

  defp payload_value(%{} = payload, key) when is_atom(key) do
    Map.get(payload, key) || Map.get(payload, Atom.to_string(key))
  end

  defp payload_value(%{} = payload, key) when is_binary(key), do: Map.get(payload, key)
  defp payload_value(_, _), do: nil

  defp normalize_invoice_id(value) when is_integer(value), do: value

  defp normalize_invoice_id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp normalize_invoice_id(_), do: nil

  defp generate_edoc(%{} = payload) do
    payload
    |> resolve_edoc_prefix()
    |> case do
      nil ->
        {:ok, nil, nil}

      {prefix, doc_type} ->
        case Accounts.next_tax_sequence(prefix) do
          {:ok, identifier} ->
            {:ok, identifier, doc_type}

          {:error, reason} ->
            Logger.error("Failed to generate E-DOC for prefix #{prefix}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp resolve_edoc_prefix(payload) do
    bill = payload_value(payload, "x_studio_e_doc_bill")
    inv = payload_value(payload, "x_studio_e_doc_inv")

    cond do
      valid_identifier?(bill) -> {bill, "BILL"}
      valid_identifier?(inv) -> {inv, "INV"}
      true -> nil
    end
  end

  defp valid_identifier?(value) when is_binary(value), do: String.trim(value) != ""
  defp valid_identifier?(_), do: false

  defp format_ip({a, b, c, d}), do: Enum.join([a, b, c, d], ".")

  defp format_ip({a, b, c, d, e, f, g, h}),
    do: :inet.ntoa({a, b, c, d, e, f, g, h}) |> to_string()

  defp format_ip(nil), do: nil

  defp format_ip(other) do
    case :inet.ntoa(other) do
      {:error, _reason} -> inspect(other)
      text -> to_string(text)
    end
  end
end
