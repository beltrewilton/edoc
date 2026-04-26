defmodule EdocWeb.CompanyTransactionsLive do
  use EdocWeb, :live_view

  alias Edoc.Accounts
  alias Edoc.Accounts.Company
  alias Edoc.Etaxcore.PayloadJson
  alias Phoenix.PubSub
  alias Decimal
  alias Jason

  @pubsub_server Edoc.PubSub
  @topic_prefix "company-transactions"

  def topic(user_id, company_id) when is_binary(user_id) and is_binary(company_id) do
    Enum.join([@topic_prefix, user_id, company_id], ":")
  end

  def topic(_, _), do: nil

  @impl true
  def mount(%{"id" => company_id}, _session, socket) do
    scope = socket.assigns.current_scope

    case load_company(scope, company_id) do
      {:ok, company, transactions} ->
        socket =
          socket
          |> assign(:company, company)
          |> assign(:page_title, "Transactions · #{company.company_name}")
          |> assign(:raw_json_payloads, default_raw_json_payloads())
          |> assign(:raw_json_tab, :odoo_request)
          |> assign(:raw_json_edoc, nil)
          |> assign(:raw_json_inserted_at, nil)
          |> stream(:transactions, transactions, reset: true)
          |> maybe_subscribe(scope, company)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That company is not available anymore.")
         |> push_navigate(to: ~p"/companies")}
    end
  end

  @impl true
  def handle_info(
        {:odoo_transaction_inserted, %{company_id: company_id, transaction: transaction}},
        %{assigns: %{company: %{id: company_id}}} = socket
      ) do
    {:noreply, stream_insert(socket, :transactions, transaction, at: 0)}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("open_raw_json", params, socket) do
    {:noreply,
     socket
     |> assign(:raw_json_payloads, %{
       odoo_request: Map.get(params, "odoo_request_payload") || "No payload yet",
       provider_request: Map.get(params, "provider_request_payload") || "No payload yet",
       provider_response: Map.get(params, "provider_response_payload") || "No payload yet"
     })
     |> assign(:raw_json_tab, :odoo_request)
     |> assign(:raw_json_edoc, Map.get(params, "edoc"))
     |> assign(:raw_json_inserted_at, Map.get(params, "inserted_at"))}
  end

  @impl true
  def handle_event("switch_raw_json_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :raw_json_tab, normalize_raw_json_tab(tab))}
  end

  @impl true
  def handle_event("close_raw_json", _params, socket) do
    {:noreply,
     socket
     |> assign(:raw_json_payloads, default_raw_json_payloads())
     |> assign(:raw_json_tab, :odoo_request)
     |> assign(:raw_json_edoc, nil)
     |> assign(:raw_json_inserted_at, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <div class="mx-auto w-full max-w-6xl space-y-5">
        <div class="flex flex-wrap items-center gap-3">
          <.button navigate={~p"/companies"} variant="secondary">
            <.icon name="hero-arrow-left" class="size-4" /> Back to companies
          </.button>
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.25em] text-slate-500 dark:text-slate-400">
              Transactions
            </p>
            <h1 class="text-2xl font-semibold tracking-tight text-slate-900 dark:text-slate-100">
              {@company.company_name}
            </h1>
          </div>
          <span class="ml-auto inline-flex rounded-full border border-slate-200 bg-slate-100 px-3 py-1 text-xs font-semibold text-slate-700 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-300">
            {format_company_rnc(@company)}
          </span>
        </div>

        <.surface>
          <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <div>
              <p class="text-xs font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">
                Status
              </p>
              <div class="mt-2 flex items-center gap-2">
                <.status_pill tone={if(@company.connected, do: "success", else: "warning")}>
                  {if(@company.connected, do: "Connected", else: "Pending")}
                </.status_pill>
                <.status_pill tone={if(@company.active, do: "info", else: "neutral")}>
                  {if(@company.active, do: "Active", else: "Inactive")}
                </.status_pill>
              </div>
            </div>
            <div>
              <p class="text-xs font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">
                Odoo URL
              </p>
              <p class="mt-1 truncate text-sm font-medium text-slate-800 dark:text-slate-200">
                {@company.odoo_url || "—"}
              </p>
            </div>
            <div>
              <p class="text-xs font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">
                Odoo user
              </p>
              <p class="mt-1 truncate text-sm font-medium text-slate-800 dark:text-slate-200">
                {@company.odoo_user || "—"}
              </p>
            </div>
            <div>
              <p class="text-xs font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">
                Updated
              </p>
              <p class="mt-1 text-sm font-medium text-slate-800 dark:text-slate-200">
                {format_timestamp(@company.updated_at)}
              </p>
            </div>
          </div>
        </.surface>

        <.surface class="p-0">
          <div class="flex flex-wrap items-center gap-3 border-b border-slate-200 px-5 py-4 dark:border-slate-800">
            <div>
              <p class="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500 dark:text-slate-400">
                Live feed
              </p>
              <h2 class="text-lg font-semibold tracking-tight text-slate-900 dark:text-slate-100">
                Latest Odoo transactions
              </h2>
            </div>
            <div class="ml-auto inline-flex items-center gap-2 rounded-full border border-emerald-200 bg-emerald-50 px-3 py-1 text-xs font-semibold text-emerald-700 dark:border-emerald-500/40 dark:bg-emerald-500/15 dark:text-emerald-300">
              <span class="size-2 animate-pulse rounded-full bg-emerald-500"></span>
              Live
            </div>
          </div>

          <div class="overflow-x-auto">
            <div class="min-w-[900px]">
              <div class="grid grid-cols-[2.2fr_1.3fr_1fr_1fr_0.85fr_9.5rem] gap-2 border-b border-slate-200 bg-slate-50 px-5 py-3 text-[0.7rem] font-semibold uppercase tracking-[0.2em] text-slate-500 dark:border-slate-800 dark:bg-slate-950/45 dark:text-slate-400">
                <p>e-DOC</p>
                <p>RNC</p>
                <p>Amount</p>
                <p>Tax</p>
                <p>Requested at</p>
                <p class="text-right">Payload</p>
              </div>

              <div id="transactions" phx-update="stream" class="divide-y divide-slate-100 dark:divide-slate-800">
                <div
                  id="transactions-empty-state"
                  class="hidden only:flex flex-col items-center justify-center gap-2 px-6 py-16 text-center text-sm text-slate-500 dark:text-slate-400"
                >
                  <.icon name="hero-receipt-percent" class="size-8 text-slate-400 dark:text-slate-500" />
                  <p>No transactions yet. Connect your automations to start streaming activity.</p>
                </div>

                <div
                  :for={{dom_id, transaction} <- @streams.transactions}
                  id={dom_id}
                  data-role="transaction-row"
                  data-rnc={rnc_column_value(transaction)}
                  class="grid grid-cols-[2.2fr_1.3fr_1fr_1fr_0.85fr_9.5rem] gap-2 px-5 py-4 text-sm transition hover:bg-slate-50 dark:hover:bg-slate-800/35"
                >
                  <div>
                    <p class="font-semibold text-slate-900 dark:text-slate-100">
                      {display_edoc(transaction)}
                    </p>
                    <p class="text-xs text-slate-500 dark:text-slate-400">
                      {display_invoice_partner_name(transaction)}
                    </p>
                    <p class="text-xs text-slate-500 dark:text-slate-400">
                      <%= if link = display_name_link(transaction, @company) do %>
                        <a
                          href={link}
                          target="_blank"
                          rel="noopener noreferrer"
                          class="group inline-flex items-center gap-1 rounded-sm px-0.5 underline decoration-slate-300 decoration-2 underline-offset-2 transition duration-200 hover:text-slate-700 hover:decoration-slate-400 dark:decoration-slate-600 dark:hover:text-slate-200 dark:hover:decoration-slate-500"
                        >
                          {display_name(transaction)}
                          <.icon
                            name="hero-arrow-top-right-on-square"
                            class="size-3.5 shrink-0 text-slate-400 transition duration-200 group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-slate-600 dark:text-slate-500 dark:group-hover:text-slate-300"
                          />
                        </a>
                      <% else %>
                        {display_name(transaction)}
                      <% end %>
                    </p>
                  </div>

                  <div class="font-medium text-slate-700 dark:text-slate-300">
                    {rnc_column_value(transaction)}
                  </div>
                  <div class="font-semibold text-emerald-700 dark:text-emerald-300">
                    <span data-field="amount">{format_currency(odoo_value(transaction, :amount))}</span>
                  </div>
                  <div class="font-semibold text-sky-700 dark:text-sky-300">
                    <span data-field="tax">{format_currency(odoo_value(transaction, :tax))}</span>
                  </div>
                  <div class="text-slate-600 dark:text-slate-300">
                    <p class="leading-tight">{format_requested_at_date(transaction.odoo_request_at)}</p>
                    <p class="text-xs leading-tight text-slate-500 dark:text-slate-400">
                      {format_requested_at_time(transaction.odoo_request_at)}
                    </p>
                  </div>

                  <div class="text-right">
                    <button
                      id={"raw-json-btn-#{transaction.id}"}
                      type="button"
                      aria-label={"Open raw JSON for transaction #{transaction.id}"}
                      phx-click={
                        JS.push("open_raw_json",
                          value: %{
                            odoo_request_payload: transaction_payload(transaction, :odoo_request),
                            provider_request_payload:
                              transaction_payload(transaction, :provider_request),
                            provider_response_payload:
                              transaction_payload(transaction, :provider_response),
                            edoc: transaction.edoc || "—",
                            inserted_at: format_timestamp_utc_minus_4(transaction.inserted_at)
                          }
                        )
                        |> show_modal("transaction-raw-json-modal")
                      }
                      class="inline-flex items-center justify-end gap-1 rounded-lg border border-slate-200 bg-white px-3 py-2 text-xs font-semibold uppercase tracking-[0.18em] text-slate-500 transition hover:border-slate-300 hover:bg-slate-50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-300 dark:hover:border-slate-600 dark:hover:bg-slate-800"
                    >
                      <.icon name="hero-code-bracket-square" class="size-4" />
                      Raw JSON
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </.surface>
      </div>

      <.modal
        id="transaction-raw-json-modal"
        closeable={false}
        on_cancel={hide_modal("transaction-raw-json-modal") |> JS.push("close_raw_json")}
      >
        <:modal_box class="w-[96vw] max-w-6xl p-0" content_class="h-[82vh]">
          <section id="transaction-raw-json-viewer" class="flex h-full flex-col">
            <header class="flex items-center gap-3 border-b border-slate-200 bg-slate-50 px-5 py-4 dark:border-slate-800 dark:bg-slate-900">
              <div class="flex-1">
                <h3 class="text-sm font-semibold uppercase tracking-[0.2em] text-slate-500 dark:text-slate-400">
                  Raw JSON payload
                </h3>
                <div class="mt-1 flex flex-wrap items-center gap-4 text-sm font-medium text-slate-800 dark:text-slate-200">
                  <span>e-DOC: {@raw_json_edoc || "—"}</span>
                  <span>{@raw_json_inserted_at || "—"}</span>
                </div>

                <div class="mt-3 inline-flex rounded-xl border border-slate-200 bg-white/90 p-1 text-xs font-semibold dark:border-slate-700 dark:bg-slate-800/80">
                  <button
                    id="raw-json-tab-odoo"
                    type="button"
                    phx-click="switch_raw_json_tab"
                    phx-value-tab="odoo_request"
                    class={[
                      "rounded-lg px-3 py-1.5 transition",
                      @raw_json_tab == :odoo_request &&
                        "bg-slate-900 text-slate-100 shadow-sm dark:bg-slate-100 dark:text-slate-900",
                      @raw_json_tab != :odoo_request &&
                        "text-slate-600 hover:text-slate-900 dark:text-slate-300 dark:hover:text-slate-100"
                    ]}
                  >
                    Odoo Request
                  </button>
                  <button
                    id="raw-json-tab-provider"
                    type="button"
                    phx-click="switch_raw_json_tab"
                    phx-value-tab="provider_request"
                    class={[
                      "rounded-lg px-3 py-1.5 transition",
                      @raw_json_tab == :provider_request &&
                        "bg-slate-900 text-slate-100 shadow-sm dark:bg-slate-100 dark:text-slate-900",
                      @raw_json_tab != :provider_request &&
                        "text-slate-600 hover:text-slate-900 dark:text-slate-300 dark:hover:text-slate-100"
                    ]}
                  >
                    Provider Request
                  </button>
                  <button
                    id="raw-json-tab-provider-response"
                    type="button"
                    phx-click="switch_raw_json_tab"
                    phx-value-tab="provider_response"
                    class={[
                      "rounded-lg px-3 py-1.5 transition",
                      @raw_json_tab == :provider_response &&
                        "bg-slate-900 text-slate-100 shadow-sm dark:bg-slate-100 dark:text-slate-900",
                      @raw_json_tab != :provider_response &&
                        "text-slate-600 hover:text-slate-900 dark:text-slate-300 dark:hover:text-slate-100"
                    ]}
                  >
                    Provider Response
                  </button>
                </div>
              </div>

              <div class="ml-auto flex items-center gap-2">
                <button
                  id="close-raw-json"
                  type="button"
                  aria-label="Close raw JSON modal"
                  phx-click={hide_modal("transaction-raw-json-modal") |> JS.push("close_raw_json")}
                  class="inline-flex h-9 w-9 items-center justify-center rounded-full border border-slate-200 bg-white text-slate-600 transition hover:border-slate-300 hover:bg-slate-100 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-300 dark:hover:border-slate-600 dark:hover:bg-slate-700"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>
            </header>

            <div
              id="transaction-raw-json-client"
              phx-hook="RawJsonViewer"
              phx-update="ignore"
              data-json={active_raw_json_payload(@raw_json_payloads, @raw_json_tab)}
              class="relative flex-1 overflow-auto bg-slate-950 px-5 py-5"
            >
              <button
                id="copy-raw-json"
                type="button"
                aria-label="Copy raw JSON"
                data-role="copy-json"
                class="absolute right-5 top-5 inline-flex h-9 w-9 items-center justify-center rounded-full border border-slate-600/80 bg-slate-900/90 text-slate-200 backdrop-blur transition hover:border-slate-500 hover:bg-slate-800"
              >
                <.icon name="hero-clipboard-document" class="size-4" />
              </button>

              <p
                data-role="copy-feedback"
                class="pointer-events-none absolute right-16 top-6 rounded-full border border-emerald-300/40 bg-emerald-400/10 px-3 py-1 text-xs font-semibold text-emerald-200 opacity-0 transition"
              >
                Copied
              </p>

              <pre
                phx-no-curly-interpolation
                class="min-h-full whitespace-pre-wrap rounded-xl border border-slate-800 bg-slate-950 p-5 font-mono text-xs leading-relaxed text-slate-100"
              ><code data-role="json-highlight"></code></pre>
            </div>
          </section>
        </:modal_box>
      </.modal>
    </Layouts.app>
    """
  end

  defp load_company(%{user: _} = scope, company_id) do
    company = Accounts.get_company_for_scope!(scope, company_id)
    {:ok, company, Accounts.list_company_transactions(scope, company)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp load_company(_, _), do: {:error, :not_found}

  defp maybe_subscribe(socket, scope, company) do
    if connected?(socket) do
      subscribe_to_transactions(socket, scope, company)
    else
      socket
    end
  end

  defp subscribe_to_transactions(socket, scope, %Company{id: company_id}) do
    with user_id when not is_nil(user_id) <- scope_user_id(scope),
         topic when not is_nil(topic) <- topic(user_id, company_id),
         :ok <- PubSub.subscribe(@pubsub_server, topic) do
      assign(socket, :transactions_topic, topic)
    else
      _ -> socket
    end
  end

  defp scope_user_id(%Accounts.Scope{user: %Accounts.User{id: user_id}})
       when is_binary(user_id) and byte_size(user_id) > 0,
       do: user_id

  defp scope_user_id(_), do: nil

  defp display_invoice_partner_name(transaction) do
    transaction
    |> odoo_value(:invoice_partner_display_name)
    |> present_string()
    |> case do
      nil -> "—"
      value -> String.upcase(value)
    end
  end

  defp display_name(transaction) do
    transaction
    |> odoo_value(:display_name)
    |> present_string() || "—"
  end

  defp display_edoc(%{edoc: edoc} = transaction) do
    present_string(edoc) ||
      transaction
      |> odoo_value(:e_doc)
      |> present_string() || "—"
  end

  defp display_edoc(transaction) do
    transaction
    |> odoo_value(:e_doc)
    |> present_string() || "—"
  end

  defp display_name_link(transaction, %Company{} = company) do
    with display_name when display_name != "—" <- display_name(transaction),
         base_url when is_binary(base_url) <- present_string(company.odoo_url),
         record_id when is_binary(record_id) <- odoo_record_id(transaction) do
      section = if emisor_rnc_edoc?(transaction), do: "bills", else: "invoicing"
      "#{String.trim_trailing(base_url, "/")}/odoo/accounting/1/#{section}/#{record_id}"
    else
      _ -> nil
    end
  end

  defp display_name_link(_, _), do: nil

  defp odoo_record_id(transaction) do
    transaction
    |> odoo_value(:odoo_id)
    |> normalize_record_id()
  end

  defp rnc_column_value(transaction) do
    if emisor_rnc_edoc?(transaction) do
      odoo_value(transaction, :rnc_emisor) || "—"
    else
      odoo_value(transaction, :partner_vat) || "—"
    end
  end

  defp odoo_value(%{odoo_request: request}, key) when is_atom(key) do
    request = request || %{}

    case key do
      :amount ->
        amount_from_payload(request)

      :tax ->
        tax_from_payload(request)

      :e_doc ->
        derive_edoc(request)

      :rnc ->
        Map.get(request, "rnc") || Map.get(request, :rnc)

      :rnc_emisor ->
        Map.get(request, "rncEmisor") ||
          Map.get(request, :rncEmisor) ||
          Map.get(request, "rnc_emisor") ||
          Map.get(request, :rnc_emisor)

      :odoo_id ->
        Map.get(request, "id") || Map.get(request, :id)

      _ ->
        Map.get(request, key) || Map.get(request, Atom.to_string(key))
    end
  end

  defp odoo_value(_, _), do: nil

  defp present_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp present_string(_), do: nil

  defp normalize_record_id(value) when is_integer(value) and value > 0,
    do: Integer.to_string(value)

  defp normalize_record_id(value) when is_binary(value) do
    trimmed = String.trim(value)

    case Integer.parse(trimmed) do
      {id, ""} when id > 0 -> Integer.to_string(id)
      _ -> nil
    end
  end

  defp normalize_record_id([value | _]), do: normalize_record_id(value)
  defp normalize_record_id(_), do: nil

  defp format_company_rnc(%Company{rnc: nil}), do: "RNC unavailable"
  defp format_company_rnc(%Company{rnc: rnc}), do: "RNC #{rnc}"

  defp format_currency(nil), do: "—"

  defp format_currency(%Decimal{} = value) do
    "RD$ " <> Decimal.to_string(value, :normal)
  end

  defp format_currency(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _rest} -> format_currency(decimal)
      :error -> value
    end
  end

  defp format_currency(value) when is_integer(value),
    do: format_currency(Decimal.new(value))

  defp format_currency(value) when is_float(value),
    do: format_currency(Decimal.from_float(value))

  defp format_currency(_), do: "—"

  defp format_timestamp(nil), do: "—"

  defp format_timestamp(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y · %H:%M UTC")
  end

  defp format_timestamp_utc_minus_4(nil), do: "—"

  defp format_timestamp_utc_minus_4(%DateTime{} = datetime) do
    datetime
    |> utc_minus_4()
    |> Calendar.strftime("%b %d, %Y · %I:%M %p")
  end

  defp format_requested_at_date(nil), do: "—"

  defp format_requested_at_date(%DateTime{} = datetime) do
    datetime
    |> utc_minus_4()
    |> Calendar.strftime("%b %d, %Y")
  end

  defp format_requested_at_time(nil), do: "—"

  defp format_requested_at_time(%DateTime{} = datetime) do
    datetime
    |> utc_minus_4()
    |> Calendar.strftime("%I:%M %p")
  end

  defp utc_minus_4(datetime), do: DateTime.add(datetime, -4 * 60 * 60, :second)

  defp default_raw_json_payloads do
    %{
      odoo_request: "No payload yet",
      provider_request: "No payload yet",
      provider_response: "No payload yet"
    }
  end

  defp normalize_raw_json_tab("provider_response"), do: :provider_response
  defp normalize_raw_json_tab(:provider_response), do: :provider_response
  defp normalize_raw_json_tab("provider_request"), do: :provider_request
  defp normalize_raw_json_tab(:provider_request), do: :provider_request
  defp normalize_raw_json_tab(_), do: :odoo_request

  defp active_raw_json_payload(payloads, :provider_response),
    do: Map.get(payloads, :provider_response, "No payload yet")

  defp active_raw_json_payload(payloads, :provider_request),
    do: Map.get(payloads, :provider_request, "No payload yet")

  defp active_raw_json_payload(payloads, _),
    do: Map.get(payloads, :odoo_request, "No payload yet")

  defp transaction_payload(transaction, field)
       when field in [:odoo_request, :provider_request, :provider_response] do
    payload = Map.get(transaction, field)
    encode_payload(payload)
  end

  defp encode_payload(nil), do: "No payload yet"

  defp encode_payload(map) when is_map(map) do
    PayloadJson.encode!(map, pretty: true)
  end

  defp encode_payload(other) do
    inspect(other, pretty: true, limit: :infinity)
  end

  defp amount_from_payload(request) do
    coerce_decimal(request["amount_total"]) ||
      fetch_nested_decimal(request, ["tax_totals", "total_amount"])
  end

  defp tax_from_payload(request) do
    coerce_decimal(request["amount_tax"]) ||
      fetch_nested_decimal(request, ["tax_totals", "tax_amount"])
  end

  defp derive_edoc(request) do
    cond do
      valid_edoc?(request["x_studio_e_doc_inv"]) ->
        request["x_studio_e_doc_inv"]

      valid_edoc?(request["x_studio_e_doc_bill"]) ->
        request["x_studio_e_doc_bill"]

      request["invoice_items"] ->
        request["invoice_items"]
        |> List.wrap()
        |> Enum.find_value(fn item ->
          cond do
            valid_edoc?(item["x_studio_e_doc_inv"]) -> item["x_studio_e_doc_inv"]
            valid_edoc?(item["x_studio_e_doc_bill"]) -> item["x_studio_e_doc_bill"]
            true -> nil
          end
        end)

      true ->
        nil
    end
  end

  defp valid_edoc?(value) when is_binary(value), do: String.trim(value) != ""
  defp valid_edoc?(_), do: false

  defp emisor_rnc_edoc?(transaction) do
    case extract_edoc_type(transaction) do
      "41" -> true
      "43" -> true
      "47" -> true
      _ -> false
    end
  end

  defp extract_edoc_type(transaction) do
    transaction
    |> display_edoc()
    |> present_string()
    |> case do
      nil ->
        nil

      value ->
        case Regex.run(~r/^E?(\d{2})/i, value) do
          [_, type] -> type
          _ -> nil
        end
    end
  end

  defp coerce_decimal(%Decimal{} = value), do: value
  defp coerce_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp coerce_decimal(value) when is_float(value), do: Decimal.from_float(value)

  defp coerce_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _rest} -> decimal
      :error -> nil
    end
  end

  defp coerce_decimal(_), do: nil

  defp fetch_nested_decimal(request, path) do
    value =
      Enum.reduce(path, request, fn key, acc ->
        case acc do
          %{} -> Map.get(acc, key)
          _ -> nil
        end
      end)

    coerce_decimal(value)
  end
end