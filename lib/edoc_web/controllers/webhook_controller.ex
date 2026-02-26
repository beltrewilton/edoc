defmodule EdocWeb.WebhookController do
  use EdocWeb, :controller

  alias Edoc.Accounts.{Company, User}
  alias Edoc.Etaxcore.InvoiceService
  alias Edoc.OdooAutomationClient, as: Odoo
  alias Edoc.Repo
  alias Edoc.TenantContext
  alias Edoc.Transaction
  alias EdocWeb.CompanyTransactionsLive
  alias Phoenix.PubSub
  require Logger

  @body_opts [length: 10_000_000, read_timeout: 15_000]
  @pubsub_server Edoc.PubSub

  def create(conn, %{"user_id" => user_id, "company_id" => company_id}) do
    with {:ok, payload} <- decode_body(conn),
         {:ok, user} <- fetch_user(user_id),
         {:ok, tenant} <- tenant_for_user(user),
         :ok <- ensure_tenant_context(tenant),
         {:ok, company} <- fetch_company(company_id, tenant),
         {:ok, enriched_payload, odoo_context} <- enrich_payload(payload, company),
         {:ok, transaction} <-
           InvoiceService.send_invoice(
             enriched_payload,
             company,
             tenant: tenant,
             odoo_context: odoo_context,
             request_log_entry: build_log_entry(conn, enriched_payload)
           ) do
      broadcast_transaction_event(user, company, transaction)

      conn
      |> put_status(:created)
      |> json(%{status: "accepted"})
    else
      {:error, :invalid_payload} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid payload"})

      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "unable to store transaction", details: errors_on(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "failed to process webhook", reason: inspect(reason)})
    end
  end

  defp decode_body(conn) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} ->
        with {:ok, raw, _conn} <- Plug.Conn.read_body(conn, @body_opts),
             {:ok, decoded} <- Jason.decode(raw),
             true <- is_map(decoded) do
          {:ok, decoded}
        else
          _ -> {:error, :invalid_payload}
        end

      %{} = params ->
        {:ok, params}
    end
  end

  defp fetch_user(user_id) do
    case Repo.get(User, user_id) do
      %User{} = user -> {:ok, user}
      _ -> {:error, :unauthorized}
    end
  end

  defp tenant_for_user(%User{tenant: tenant}) when is_binary(tenant) and byte_size(tenant) > 0,
    do: {:ok, tenant}

  defp tenant_for_user(_), do: {:error, :unauthorized}

  defp fetch_company(company_id, tenant) do
    case Repo.get(Company, company_id, prefix: tenant) do
      %Company{} = company -> {:ok, company}
      _ -> {:error, :unauthorized}
    end
  end

  defp enrich_payload(payload, %Company{} = company) do
    case payload_invoice_id(payload) do
      nil ->
        {:ok, payload, nil}

      invoice_id ->
        with {:ok, client, uid} <- build_odoo_context(company),
             enriched_payload <- enrich_with_invoice_items(client, uid, invoice_id, payload) do
          {:ok, enriched_payload, {client, uid}}
        end
    end
  rescue
    exception ->
      Logger.error("Failed to enrich payload with Odoo invoice lines: #{Exception.message(exception)}")
      {:error, exception}
  end

  defp build_odoo_context(%Company{} = company) do
    client = Odoo.new(company.odoo_url, company.odoo_db, company.odoo_user, company.odoo_apikey)
    uid = Odoo.authenticate!(client)
    {:ok, client, uid}
  rescue
    exception ->
      Logger.error("Failed to authenticate against Odoo: #{Exception.message(exception)}")
      {:error, exception}
  end

  defp enrich_with_invoice_items(%Odoo{} = client, uid, invoice_id, payload) do
    invoice_items =
      client
      |> Odoo.get_invoice_data(uid, invoice_id)
      |> case do
        nil -> []
        result -> Map.get(result, :lines, [])
      end
      |> Enum.reject(&match?(%{"product_id" => false}, &1))

    Map.put(payload, "invoice_items", invoice_items)
  end

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

  defp build_log_entry(conn, payload) do
    headers_map =
      conn.req_headers
      |> Map.new(fn {key, value} -> {"header_" <> key, value} end)

    base_entry = %{
      ts: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      ip: format_ip(conn.remote_ip),
      method: conn.method,
      path: conn.request_path,
      headers: Map.new(conn.req_headers),
      body: payload
    }

    Map.merge(base_entry, headers_map)
  end

  defp format_ip({a, b, c, d}), do: Enum.join([a, b, c, d], ".")
  defp format_ip(other), do: to_string(:inet.ntoa(other))

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp broadcast_transaction_event(
         %User{id: user_id},
         %Company{id: company_id},
         %Transaction{} = transaction
       )
       when is_binary(user_id) and byte_size(user_id) > 0 and
              is_binary(company_id) and byte_size(company_id) > 0 do
    if topic = CompanyTransactionsLive.topic(user_id, company_id) do
      event =
        {:odoo_transaction_inserted,
         %{user_id: user_id, company_id: company_id, transaction: transaction}}

      PubSub.broadcast(@pubsub_server, topic, event)
    end

    :ok
  end

  defp broadcast_transaction_event(_, _, _), do: :ok

  defp ensure_tenant_context(tenant) do
    TenantContext.put_tenant(tenant)
    :ok
  end
end
