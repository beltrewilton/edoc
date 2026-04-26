defmodule Edoc.Etaxcore.InvoiceService do
  @moduledoc """
  Orchestrates eTaxCore invoice delivery and persistence.
  """

  alias Edoc.Accounts
  alias Edoc.Accounts.Company
  alias Edoc.Etaxcore.PayloadMapper
  alias Edoc.Etaxcore.PayloadJson
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
             company,
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
    request_payload =
      payload
      |> PayloadMapper.map_invoice(company, e_doc: e_doc)
      |> stringify_rnc_fields()

    {:ok, request_payload}
  end

  defp stringify_rnc_fields(%{"encabezado" => encabezado} = request_payload)
       when is_map(encabezado) do
    updated_encabezado =
      encabezado
      |> stringify_nested_field("emisor", "rncEmisor")
      |> stringify_nested_field("comprador", "rncComprador")

    Map.put(request_payload, "encabezado", updated_encabezado)
  end

  defp stringify_rnc_fields(request_payload), do: request_payload

  defp stringify_nested_field(parent, child_key, field_key) do
    case Map.get(parent, child_key) do
      child when is_map(child) -> Map.put(parent, child_key, stringify_field(child, field_key))
      _ -> parent
    end
  end

  defp stringify_field(map, field_key) do
    case Map.get(map, field_key) do
      nil -> map
      false -> map
      value -> Map.put(map, field_key, to_string(value))
    end
  end

  defp dispatch_request(
         %Transaction{} = transaction,
         %Company{} = company,
         tenant,
         request_payload,
         payload,
         odoo_context,
         e_doc,
         doc_type
       ) do
    request_at = DateTime.utc_now(:second)

    print_json("request_payload", request_payload)
    print_json("payload", payload)

    provider_result =
      case maybe_add_odoo_invoice_sequence(odoo_context, payload, e_doc, doc_type) do
        :ok -> safe_send_invoice(request_payload, company)
        {:error, reason} -> {:error, {:odoo_invoice_action_error, reason}}
      end

    maybe_add_odoo_provider_response_note(odoo_context, payload, provider_result)

    normalized_provider_response = normalize_provider_response(provider_result)

    case persist_provider_exchange(
           transaction,
           tenant,
           request_payload,
           request_at,
           normalized_provider_response
         ) do
      :ok ->
        case provider_result do
          {:ok, _body} ->
            {:ok,
             %{
               transaction: transaction,
               provider_response: normalized_provider_response
             }}

          {:error, _reason} ->
            {:error,
             %{
               transaction: transaction,
               provider_response: normalized_provider_response
             }}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp maybe_add_odoo_invoice_sequence(odoo_context, payload, e_doc, doc_type) do
    case payload_invoice_id(payload) do
      nil ->
        :ok

      invoice_id ->
        do_add_odoo_invoice_sequence(odoo_context, invoice_id, e_doc, doc_type)
    end
  end

  defp do_add_odoo_invoice_sequence({%Odoo{} = client, uid}, invoice_id, e_doc, doc_type) do
    try do
      maybe_add_invoice_sequence(client, uid, invoice_id, e_doc, doc_type)
      :ok
    rescue
      exception ->
        Logger.error("Failed to add Odoo invoice sequence: #{Exception.message(exception)}")
        {:error, exception}
    end
  end

  defp do_add_odoo_invoice_sequence(nil, invoice_id, _e_doc, _doc_type) do
    Logger.warning(
      "Skipping Odoo invoice sequence due to missing Odoo context for invoice #{inspect(invoice_id)}"
    )

    :ok
  end

  defp do_add_odoo_invoice_sequence(_other, invoice_id, _e_doc, _doc_type) do
    Logger.warning(
      "Skipping Odoo invoice sequence due to invalid Odoo context for invoice #{inspect(invoice_id)}"
    )

    :ok
  end

  defp maybe_add_invoice_sequence(_client, _uid, _invoice_id, e_doc, doc_type)
       when is_nil(e_doc) or is_nil(doc_type),
       do: :ok

  defp maybe_add_invoice_sequence(%Odoo{} = client, uid, invoice_id, e_doc, doc_type) do
    Odoo.add_invoice_sequence(client, uid, invoice_id, e_doc, doc_type)
  end

  defp maybe_add_odoo_provider_response_note(_odoo_context, _payload, {:error, _reason}), do: :ok

  defp maybe_add_odoo_provider_response_note(odoo_context, payload, {:ok, provider_body}) do
    case payload_invoice_id(payload) do
      nil ->
        :ok

      invoice_id ->
        do_add_odoo_provider_response_note(odoo_context, invoice_id, provider_body)
    end
  end

  defp do_add_odoo_provider_response_note({%Odoo{} = client, uid}, invoice_id, provider_body) do
    note = provider_response_note(provider_body)

    try do
      Odoo.add_invoice_log_note(client, uid, invoice_id, note)
      :ok
    rescue
      exception ->
        Logger.warning(
          "Failed to add Odoo provider response note for invoice #{inspect(invoice_id)}: #{Exception.message(exception)}"
        )

        :ok
    end
  end

  defp do_add_odoo_provider_response_note(nil, invoice_id, _provider_body) do
    Logger.warning(
      "Skipping Odoo provider response note due to missing Odoo context for invoice #{inspect(invoice_id)}"
    )

    :ok
  end

  defp do_add_odoo_provider_response_note(_other, invoice_id, _provider_body) do
    Logger.warning(
      "Skipping Odoo provider response note due to invalid Odoo context for invoice #{inspect(invoice_id)}"
    )

    :ok
  end

  defp provider_response_note(provider_body) when is_map(provider_body) do
    estado =
      nested_value(provider_body, ["result", "estado"]) ||
        nested_value(provider_body, ["result", "msj", "estado"])

    fecha_recepcion =
      nested_value(provider_body, ["result", "fechaRecepcion"]) ||
        nested_value(provider_body, ["result", "msj", "fechaRecepcion"])

    qr_data = nested_value(provider_body, ["result", "qrData"])

    messages =
      provider_body
      |> provider_response_messages()
      |> Enum.map(&provider_message_text/1)
      |> Enum.reject(&is_nil/1)

    note_html_section(
      "Información DGII",
      [
        note_html_status_line(string_or_default(estado, "N/A")),
        note_html_line("Fecha Recepción", fecha_recepcion),
        note_html_line("Messages", Enum.join(messages, "; ")),
        note_html_link_line("QR Data", qr_data)
      ]
    )
  end

  defp provider_response_note(_provider_body) do
    note_html_section("Información DGII", [note_html_status_line("N/A")])
  end

  defp safe_send_invoice(payload, %Company{} = company) do
    EtaxcoreClient.send_invoice(payload, company)
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

  defp normalize_provider_response({:error, {:missing_provider_config, field}}) do
    %{
      "status" => "error",
      "type" => "missing_provider_config",
      "field" => to_string(field)
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
      case encode_log_json(value) do
        {:ok, json} -> json
        {:error, _reason} -> inspect(value, pretty: true, limit: :infinity)
      end

    IO.puts("#{label}:")
    IO.puts(output)
  end

  defp encode_log_json(value) when is_map(value), do: PayloadJson.encode(value, pretty: true)
  defp encode_log_json(value), do: Jason.encode(value, pretty: true)

  defp format_reason(%_{__exception__: true} = exception), do: Exception.message(exception)
  defp format_reason(reason), do: inspect(reason)

  defp provider_response_messages(provider_body) when is_map(provider_body) do
    direct_messages = list_or_empty(Map.get(provider_body, "messages"))

    nested_messages =
      provider_body
      |> nested_value(["result", "msj", "mensajes"])
      |> list_or_empty()

    direct_messages ++ nested_messages
  end

  defp nested_value(value, []), do: value

  defp nested_value(%{} = value, [key | rest]) when is_binary(key) do
    value
    |> Map.get(key)
    |> nested_value(rest)
  end

  defp nested_value(%{} = value, [key | rest]) when is_atom(key) do
    value
    |> Map.get(key)
    |> nested_value(rest)
  end

  defp nested_value(_, _), do: nil

  defp note_html_section(title, items) do
    list_items =
      items
      |> Enum.reject(&is_nil/1)
      |> Enum.join()

    "<p><strong>#{html_text(title)}</strong></p><ul>#{list_items}</ul>"
  end

  defp note_html_line(_label, nil), do: nil
  defp note_html_line(_label, ""), do: nil

  defp note_html_line(label, value) do
    "<li><strong>#{html_text(label)}:</strong> #{html_text(value)}</li>"
  end

  defp note_html_status_line(nil), do: nil
  defp note_html_status_line(""), do: nil

  defp note_html_status_line(status) do
    check_html =
      if status == "Aceptado" do
        " <span style=\"color: #16a34a;\">&#10003;</span>"
      else
        ""
      end

    "<li><strong>Estado:</strong> #{html_text(status)}#{check_html}</li>"
  end

  defp note_html_link_line(_label, nil), do: nil
  defp note_html_link_line(_label, ""), do: nil

  defp note_html_link_line(label, url) do
    raw_url = html_text(url)

    "<li><strong>#{html_text(label)}:</strong> <a href=\"#{raw_url}\" target=\"_blank\" rel=\"noopener noreferrer\">Consultar &#128279;</a></li>"
  end

  defp html_text(value), do: to_string(value)

  defp list_or_empty(value) when is_list(value), do: value
  defp list_or_empty(_value), do: []

  defp provider_message_text(%{} = message) do
    string_or_nil(
      Map.get(message, "valor") ||
        Map.get(message, "message") ||
        Map.get(message, "descripcion") ||
        Map.get(message, "detail")
    )
  end

  defp provider_message_text(message), do: string_or_nil(message)

  defp string_or_nil(nil), do: nil
  defp string_or_nil(false), do: nil

  defp string_or_nil(%{} = value) do
    value
    |> Map.values()
    |> Enum.map(&string_or_nil/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> string_or_nil()
  end

  defp string_or_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp string_or_nil(value), do: value |> to_string() |> string_or_nil()

  defp string_or_default(value, default) do
    case string_or_nil(value) do
      nil -> default
      present -> present
    end
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