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
  @partner_as_comprador_tipos [31, 32, 33, 34, 44, 45, 46]
  @partner_as_emisor_tipos [41, 43, 47]
  @referenced_ncf_tipos [33, 34]

  def create(conn, %{"user_id" => user_id, "company_id" => company_id}) do
    with {:ok, payload} <- decode_body(conn),
         {:ok, user} <- fetch_user(user_id),
         {:ok, tenant} <- tenant_for_user(user),
         :ok <- ensure_tenant_context(tenant),
         {:ok, company} <- fetch_company(company_id, tenant),
         {:ok, enriched_payload, odoo_context} <- enrich_payload(payload, company),
         {:ok, %{transaction: transaction}} <-
           InvoiceService.send_invoice(
             enriched_payload,
             company,
             tenant: tenant,
             odoo_context: odoo_context,
             request_context: request_context(conn)
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

      {:error, %{provider_response: provider_response}} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "failed to send invoice to etaxcore", details: provider_response})

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
             invoice_data <- Odoo.get_invoice_data(client, uid, invoice_id),
             enriched_payload <-
               payload
               |> enrich_with_invoice_items(invoice_data)
               |> enrich_with_invoice_partner(client, uid, invoice_data)
               |> enrich_with_referenced_ncf_data(client, uid) do
          {:ok, enriched_payload, {client, uid}}
        end
    end
  rescue
    exception ->
      Logger.error(
        "Failed to enrich payload with Odoo invoice lines: #{Exception.message(exception)}"
      )

      {:error, exception}
  end

  defp build_odoo_context(%Company{} = company) do
    client = Odoo.new(company)
    uid = Odoo.authenticate!(client)
    {:ok, client, uid}
  rescue
    exception ->
      Logger.error("Failed to authenticate against Odoo: #{Exception.message(exception)}")
      {:error, exception}
  end

  defp enrich_with_invoice_items(payload, invoice_data) do
    invoice_items =
      invoice_data
      |> case do
        nil -> []
        result -> Map.get(result, :lines, [])
      end
      |> Enum.reject(&match?(%{"product_id" => false}, &1))

    Map.put(payload, "invoice_items", invoice_items)
  end

  defp enrich_with_invoice_partner(payload, %Odoo{} = client, uid, invoice_data) do
    with partner_id when is_integer(partner_id) <- invoice_partner_id(invoice_data),
         role when role in [:comprador, :emisor] <- partner_mapping_role(payload),
         %{} = partner <- Odoo.get_invoice_partner_data(client, uid, partner_id) do
      payload
      |> Map.merge(partner_payload(role, partner))
    else
      _ -> payload
    end
  end

  defp enrich_with_referenced_ncf_data(payload, %Odoo{} = client, uid) do
    case resolve_tipo_ecf(payload) do
      tipo when tipo in @referenced_ncf_tipos ->
        payload
        |> put_reversed_entry_ncf(client, uid)
        |> put_modification_reason_from_ref()

      _ ->
        payload
    end
  end

  defp put_reversed_entry_ncf(payload, %Odoo{} = client, uid) do
    case reversed_entry_invoice_id(payload) do
      nil ->
        payload

      reversed_invoice_id ->
        reversed_ref =
          client
          |> Odoo.get_invoice_data(uid, reversed_invoice_id)
          |> reversed_invoice_ref()

        put_if_present(payload, "ncfModificado", reversed_ref)
    end
  end

  defp put_modification_reason_from_ref(payload) do
    ref = normalize_payload_string(payload_value(payload, "ref")) || ""
    Map.put(payload, "razonModificacion", ref)
  end

  defp reversed_entry_invoice_id(payload) do
    payload
    |> payload_value("reversed_entry_id")
    |> normalize_odoo_reference_id()
  end

  defp reversed_invoice_ref(%{invoice: %{} = invoice}) do
    invoice
    |> Map.get("ref")
    |> normalize_payload_string()
  end

  defp reversed_invoice_ref(_), do: nil

  defp invoice_partner_id(%{invoice: %{} = invoice}) do
    invoice
    |> Map.get("partner_id")
    |> normalize_odoo_reference_id()
  end

  defp invoice_partner_id(_), do: nil

  defp normalize_odoo_reference_id([id | _rest]) when is_integer(id), do: id
  defp normalize_odoo_reference_id([id | _rest]) when is_binary(id), do: normalize_invoice_id(id)
  defp normalize_odoo_reference_id(id) when is_integer(id), do: id

  defp normalize_odoo_reference_id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp normalize_odoo_reference_id(_), do: nil

  defp partner_mapping_role(payload) do
    case resolve_tipo_ecf(payload) do
      tipo when tipo in @partner_as_comprador_tipos -> :comprador
      tipo when tipo in @partner_as_emisor_tipos -> :emisor
      _ -> nil
    end
  end

  defp resolve_tipo_ecf(payload) do
    ["x_studio_e_doc_bill", "x_studio_e_doc_inv", "x_studio_e_doc"]
    |> Enum.find_value(fn key ->
      payload
      |> payload_value(key)
      |> parse_tipo_ecf()
    end)
  end

  defp parse_tipo_ecf(value) when is_binary(value) do
    case Regex.run(~r/^E?(\d{2})/, String.trim(value)) do
      [_, digits] -> String.to_integer(digits)
      _ -> nil
    end
  end

  defp parse_tipo_ecf(_), do: nil

  defp partner_payload(role, partner) do
    vat = partner_value(partner, "vat")
    name = partner_name(partner)
    address = partner_address(partner)
    phones = partner_phone_list(partner)

    base_map =
      case role do
        :comprador ->
          %{}
          |> put_if_present("rncComprador", vat)
          |> put_if_present("razonSocialComprador", name)
          |> put_if_present("direccionComprador", address)
          |> put_if_present("direccion_comprador", address)
          |> put_if_present("partner_vat", vat)
          |> put_if_present("partner_address", address)
          |> put_if_present("invoice_partner_display_name", name)

        :emisor ->
          %{}
          |> put_if_present("rncEmisor", vat)
          |> put_if_present("razonSocialEmisor", name)
          |> put_if_present("nombreComercial", name)
          |> put_if_present("direccionEmisor", address)

        _ ->
          %{}
      end

    case {role, phones} do
      {_, []} ->
        base_map

      {:comprador, _} ->
        Map.put(base_map, "tablaTelefonoComprador", phones)

      {:emisor, _} ->
        Map.put(base_map, "tablaTelefonoEmisor", phones)

      _ ->
        base_map
    end
  end

  defp partner_name(partner) do
    ["name", "company_name", "display_name"]
    |> Enum.find_value(&partner_value(partner, &1))
  end

  defp partner_address(partner) do
    city = normalize_partner_string(Map.get(partner, "city"))

    contact_address_complete =
      normalize_partner_string(Map.get(partner, "contact_address_complete"))

    cond do
      is_nil(city) and is_nil(contact_address_complete) ->
        nil

      is_nil(city) ->
        contact_address_complete

      is_nil(contact_address_complete) ->
        city

      String.contains?(
        String.downcase(contact_address_complete),
        String.downcase(city)
      ) ->
        contact_address_complete

      true ->
        city <> ", " <> contact_address_complete
    end
  end

  defp partner_phone_list(partner) do
    partner
    |> partner_value("phone")
    |> case do
      nil ->
        []

      phone when is_binary(phone) ->
        phone
        |> String.split([",", ";"], trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()

      _ ->
        []
    end
  end

  defp partner_value(partner, field) do
    partner
    |> Map.get(field)
    |> case do
      nil -> nil
      false -> nil
      value when is_binary(value) -> String.trim(value)
      value when is_integer(value) or is_float(value) -> to_string(value)
      value -> value
    end
  end

  defp normalize_partner_string(nil), do: nil
  defp normalize_partner_string(false), do: nil

  defp normalize_partner_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_partner_string(value) when is_integer(value) or is_float(value),
    do: to_string(value)

  defp normalize_partner_string(_), do: nil

  defp normalize_payload_string(nil), do: nil
  defp normalize_payload_string(false), do: nil

  defp normalize_payload_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_payload_string(value) when is_integer(value) or is_float(value),
    do: to_string(value)

  defp normalize_payload_string(_), do: nil

  defp put_if_present(map, _key, value) when value in [nil, "", []], do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

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

  defp request_context(conn) do
    %{
      method: conn.method,
      path: conn.request_path,
      remote_ip: conn.remote_ip,
      headers: conn.req_headers
    }
  end

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
