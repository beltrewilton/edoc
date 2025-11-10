defmodule EdocWeb.WebhookController do
  use EdocWeb, :controller

  alias Edoc.OdooAutomationClient, as: Odoo

  def create(conn, _params) do
    params =
      case conn.body_params do
        %Plug.Conn.Unfetched{} ->
          {:ok, raw, _conn} = Plug.Conn.read_body(conn, length: 10_000_000, read_timeout: 15_000)
          Jason.decode!(raw)

        other ->
          other
      end

    client = Odoo.new()
    uid = Odoo.authenticate!(client)

    invoice_id = params["_id"]

    invoice_items = Odoo.get_invoice_data(client, uid, invoice_id)
    invoice_items = invoice_items.lines |> Enum.reject(&(&1["product_id"] == false))
    params = Map.put(params, "invoice_items", invoice_items)

    headers_map =
      conn.req_headers
      |> Map.new(fn {key, value} -> {"header_" <> key, value} end)

    base_entry = %{
      ts: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      ip: format_ip(conn.remote_ip),
      method: conn.method,
      path: conn.request_path,
      headers: Map.new(conn.req_headers),
      body: params
    }

    entry = Map.merge(base_entry, headers_map)

    Task.start(fn ->
      Process.sleep(5_000)
      request_fmp_api(client, uid, invoice_id, params)
    end)

    case Edoc.RequestLogger.append(entry) do
      :ok ->
        json(conn, %{status: "ok"})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{status: "error", reason: inspect(reason)})
    end
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
         } = _body
       ) do
    e_doc =
      if bill == false do
        "#{inv}000000067"
      else
        "#{bill}00000078"
      end

    Odoo.append_to_invoice_name(client, uid, invoice_id, e_doc)
  end
end
