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
  alias Edoc.TenantContext
  alias Edoc.Transaction
  require Logger

  @dispatch_delay_ms 5_000

  @type odoo_context :: {Odoo.t(), integer()} | nil

  @spec send_invoice(map(), Company.t(), keyword()) ::
          {:ok, Transaction.t()} | {:error, term()}
  def send_invoice(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    tenant = Keyword.fetch!(opts, :tenant)
    request_log_entry = Keyword.get(opts, :request_log_entry)
    odoo_context = Keyword.get(opts, :odoo_context)

    with :ok <- maybe_log_request(request_log_entry),
         {:ok, e_doc, doc_type} <- generate_edoc(payload),
         {:ok, transaction} <- insert_transaction(company, tenant, payload, e_doc) do
      maybe_dispatch_request(transaction, tenant, payload, company, odoo_context, e_doc, doc_type)
      {:ok, transaction}
    end
  end

  defp maybe_log_request(nil), do: :ok

  defp maybe_log_request(%{} = entry) do
    RequestLogger.append(entry)
  rescue
    exception -> {:error, {:request_log_error, exception}}
  end

  defp maybe_dispatch_request(
         %Transaction{} = transaction,
         tenant,
         payload,
         %Company{} = company,
         odoo_context,
         e_doc,
         doc_type
       ) do
    if valid_identifier?(e_doc) and valid_identifier?(doc_type) do
      Task.start(fn ->
        TenantContext.put_tenant(tenant)
        Process.sleep(@dispatch_delay_ms)

        send_to_provider(
          transaction,
          tenant,
          payload,
          company,
          odoo_context,
          e_doc,
          doc_type
        )
      end)
    else
      :ok
    end
  end

  defp send_to_provider(
         %Transaction{} = tx,
         tenant,
         payload,
         %Company{} = company,
         odoo_context,
         e_doc,
         doc_type
       ) do
    request_payload = PayloadMapper.map_invoice(payload, company, e_doc: e_doc, doc_type: doc_type)
    request_at = DateTime.utc_now(:second)

    log_payloads_as_json(payload, request_payload)

    result =
      case maybe_update_odoo_sequence(odoo_context, payload, e_doc, doc_type) do
        :ok -> %{}
          # safe_send_invoice(request_payload)

        {:error, reason} ->
          {:error, {:odoo_sequence_update_error, reason}}
      end

    # persist_provider_exchange(tx, tenant, request_payload, request_at, result)
    result
  end

  defp maybe_update_odoo_sequence(odoo_context, payload, e_doc, doc_type) do
    case payload_invoice_id(payload) do
      nil ->
        :ok

      invoice_id ->
        do_update_odoo_sequence(odoo_context, invoice_id, e_doc, doc_type)
    end
  end

  defp do_update_odoo_sequence({%Odoo{} = client, uid}, invoice_id, e_doc, doc_type) do
    try do
      Odoo.add_invoice_sequence(client, uid, invoice_id, e_doc, doc_type)
      :ok
    rescue
      exception ->
        Logger.error("Failed to update invoice sequence in Odoo: #{Exception.message(exception)}")
        {:error, exception}
    end
  end

  defp do_update_odoo_sequence(nil, invoice_id, _e_doc, _doc_type) do
    Logger.warning(
      "Skipping Odoo sequence update due to missing Odoo context for invoice #{inspect(invoice_id)}"
    )

    :ok
  end

  defp do_update_odoo_sequence(_other, invoice_id, _e_doc, _doc_type) do
    Logger.warning(
      "Skipping Odoo sequence update due to invalid Odoo context for invoice #{inspect(invoice_id)}"
    )

    :ok
  end

  defp safe_send_invoice(payload) do
    EtaxcoreClient.send_invoice(payload)
  rescue
    exception ->
      Logger.error("eTaxCore request failed with exception: #{Exception.message(exception)}")
      {:error, {:client_exception, exception}}
  end

  defp insert_transaction(%Company{id: company_id}, tenant, payload, e_doc \\ nil) do
    attrs = %{
      company_id: company_id,
      odoo_request: payload,
      odoo_request_at: DateTime.utc_now(:second),
      edoc: e_doc
    }

    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Repo.insert(prefix: tenant)
  end

  defp persist_provider_exchange(%Transaction{} = tx, tenant, request_payload, request_at, result) do
    {response_payload, response_at} = format_provider_response(result)

    attrs = %{
      provider_request: request_payload,
      provider_request_at: request_at,
      provider_response: response_payload,
      provider_response_at: response_at
    }

    tx
    |> Transaction.changeset(attrs)
    |> Repo.update(prefix: tenant)
    |> case do
      {:ok, _transaction} ->
        :ok

      {:error, changeset} ->
        Logger.error(
          "Failed to persist provider exchange for transaction #{tx.id}: #{inspect(changeset.errors)}"
        )

        :error
    end
  end

  defp format_provider_response({:ok, response}) do
    {%{"status" => "ok", "body" => response}, DateTime.utc_now(:second)}
  end

  defp format_provider_response({:error, {:http_error, status, body}}) do
    {%{"status" => "error", "type" => "http_error", "status_code" => status, "body" => body},
     DateTime.utc_now(:second)}
  end

  defp format_provider_response({:error, {:odoo_sequence_update_error, reason}}) do
    {%{"status" => "error", "type" => "odoo_sequence_update_error", "reason" => format_reason(reason)},
     DateTime.utc_now(:second)}
  end

  defp format_provider_response({:error, {:client_exception, exception}}) do
    {%{"status" => "error", "type" => "client_exception", "reason" => Exception.message(exception)},
     DateTime.utc_now(:second)}
  end

  defp format_provider_response({:error, reason}) do
    {%{"status" => "error", "type" => "transport_error", "reason" => format_reason(reason)},
     DateTime.utc_now(:second)}
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

  defp log_payloads_as_json(payload, request_payload) do
    Logger.debug("""
    Odoo payload JSON:
    #{to_pretty_json(payload)}

    eTaxCore request payload JSON:
    #{to_pretty_json(request_payload)}
    """)
  end

  defp to_pretty_json(value) when is_map(value) do
    case Jason.encode(value, pretty: true) do
      {:ok, json} -> json
      {:error, _reason} -> inspect(value, pretty: true, limit: :infinity)
    end
  end

  defp to_pretty_json(value), do: inspect(value, pretty: true, limit: :infinity)
end
