defmodule EdocWeb.WebhookController do
  use EdocWeb, :controller

  alias Edoc.Accounts.{Company, User}
  alias Edoc.Transaction
  alias Edoc.Repo
  alias Edoc.RequestLogger
  alias Edoc.OdooAutomationClient, as: Odoo
  alias EdocWeb.CompanyTransactionsLive
  alias Phoenix.PubSub

  @body_opts [length: 10_000_000, read_timeout: 15_000]
  @pubsub_server Edoc.PubSub

  def create(conn, %{"user_id" => user_id, "company_id" => company_id}) do
    with {:ok, payload} <- decode_body(conn),
         {:ok, user} <- fetch_user(user_id),
         {:ok, tenant} <- tenant_for_user(user),
         {:ok, company} <- fetch_company(company_id, tenant),
         {:ok, enriched_payload, client_info} <- enrich_payload(conn, payload, company),
         {:ok, transaction} <- insert_transaction(company, tenant, enriched_payload) do
      broadcast_transaction_event(user, company, transaction)
      trigger_request_fmp(client_info, payload["_id"], enriched_payload)

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
        |> json(%{error: "failed to store transaction", reason: inspect(reason)})
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

  defp tenant_for_user(%User{tenant: tenant}) when is_binary(tenant) and byte_size(tenant) > 0 do
    {:ok, tenant}
  end

  defp tenant_for_user(_), do: {:error, :unauthorized}

  defp fetch_company(company_id, tenant) do
    case Repo.get(Company, company_id, prefix: tenant) do
      %Company{} = company -> {:ok, company}
      _ -> {:error, :unauthorized}
    end
  end

  defp insert_transaction(%Company{id: company_id}, tenant, payload) do
    attrs = %{
      company_id: company_id,
      odoo_request: payload,
      odoo_request_at: DateTime.utc_now(:second)
    }

    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Repo.insert(prefix: tenant)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp enrich_payload(conn, payload, company) do
    client = Odoo.new(company.odoo_url, company.odoo_db, company.odoo_user, company.odoo_apikey)
    uid = Odoo.authenticate!(client)

    payload =
      case payload["_id"] do
        nil ->
          payload

        invoice_id ->
          invoice_items =
            client
            |> Odoo.get_invoice_data(uid, invoice_id)
            |> Map.get(:lines, [])
            |> Enum.reject(&match?(%{"product_id" => false}, &1))

          Map.put(payload, "invoice_items", invoice_items)
      end

    entry = build_log_entry(conn, payload)

    case RequestLogger.append(entry) do
      :ok -> {:ok, payload, {client, uid}}
      {:error, reason} -> {:error, reason}
    end
  end

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

  defp trigger_request_fmp({_client, _uid}, nil, _payload), do: :ok

  defp trigger_request_fmp({client, uid}, invoice_id, payload) do
    Task.start(fn ->
      Process.sleep(5_000)
      request_fmp_api(client, uid, invoice_id, payload)
    end)
  end

  defp format_ip({a, b, c, d}), do: Enum.join([a, b, c, d], ".")
  defp format_ip(other), do: to_string(:inet.ntoa(other))

  defp request_fmp_api(
         %Odoo{} = client,
         uid,
         invoice_id,
         %{
           "x_studio_e_doc_bill" => bill,
           "x_studio_e_doc_inv" => inv
         }
       ) do
    e_doc =
      if bill == false do
        "#{inv}000000067"
      else
        "#{bill}00000078"
      end

    Odoo.append_to_invoice_name(client, uid, invoice_id, e_doc)
  end

  defp request_fmp_api(_, _, _, _), do: :ok

  defp broadcast_transaction_event(
         %User{id: user_id},
         %Company{id: company_id},
         %Transaction{} = transaction
       )
       when is_binary(user_id) and byte_size(user_id) > 0 and
              is_binary(company_id) and byte_size(company_id) > 0 do
    if topic = CompanyTransactionsLive.topic(user_id, company_id) do
      event = {:odoo_transaction_inserted, %{user_id: user_id, company_id: company_id, transaction: transaction}}
      PubSub.broadcast(@pubsub_server, topic, event)
    end

    :ok
  end

  defp broadcast_transaction_event(_, _, _), do: :ok
end
