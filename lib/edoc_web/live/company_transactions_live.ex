defmodule EdocWeb.CompanyTransactionsLive do
  use EdocWeb, :live_view

  alias Edoc.Accounts
  alias Edoc.Accounts.Company
  alias Decimal
  alias Jason

  @impl true
  def mount(%{"id" => company_id}, _session, socket) do
    scope = socket.assigns.current_scope

    case load_company(scope, company_id) do
      {:ok, company, transactions} ->
        socket =
          socket
          |> assign(:company, company)
          |> assign(:page_title, "Transactions · #{company.company_name}")
          |> stream(:transactions, transactions, reset: true)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That company is not available anymore.")
         |> push_navigate(to: ~p"/companies")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-6xl mx-auto px-4 py-6 space-y-6">
        <div class="flex flex-wrap items-center gap-3">
          <.button navigate={~p"/companies"} class="btn btn-ghost btn-sm gap-1 text-sm">
            <.icon name="hero-arrow-left" class="size-4" /> Back to companies
          </.button>

          <div>
            <p class="text-xs uppercase tracking-[0.35em] text-zinc-400">Transactions</p>
            <h1 class="text-2xl font-semibold text-white">{@company.company_name}</h1>
          </div>

          <span class="badge badge-outline badge-sm ml-auto text-xs font-medium tracking-wide">
            {format_company_rnc(@company)}
          </span>
        </div>

        <div class="rounded-2xl border border-white/10 bg-white/5 p-5 text-sm text-white shadow-2xl backdrop-blur-sm">
          <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <div>
              <p class="text-xs uppercase tracking-[0.3em] text-zinc-400">Status</p>
              <p class="mt-1 flex items-center gap-2 text-base font-semibold">
                <span class={[
                  "badge badge-sm",
                  @company.connected && "badge-success",
                  !@company.connected && "badge-ghost"
                ]}>
                  {(@company.connected && "Connected") || "Pending"}
                </span>
                <span class={[
                  "badge badge-sm",
                  @company.active && "badge-primary badge-outline",
                  !@company.active && "badge-ghost"
                ]}>
                  {(@company.active && "Active") || "Inactive"}
                </span>
              </p>
            </div>
            <div>
              <p class="text-xs uppercase tracking-[0.3em] text-zinc-400">Odoo URL</p>
              <p class="mt-1 truncate font-semibold text-base text-white">
                {@company.odoo_url || "—"}
              </p>
            </div>
            <div>
              <p class="text-xs uppercase tracking-[0.3em] text-zinc-400">Odoo user</p>
              <p class="mt-1 truncate font-semibold text-base text-white">
                {@company.odoo_user || "—"}
              </p>
            </div>
            <div>
              <p class="text-xs uppercase tracking-[0.3em] text-zinc-400">Updated</p>
              <p class="mt-1 font-semibold text-base text-white">
                {format_timestamp(@company.updated_at)}
              </p>
            </div>
          </div>
        </div>

        <div class="rounded-2xl border border-white/10 bg-gradient-to-b from-zinc-900/70 to-zinc-900/40 p-5 shadow-2xl">
          <div class="flex flex-wrap items-center gap-4 border-b border-white/10 pb-4">
            <div>
              <p class="text-sm uppercase tracking-[0.25em] text-zinc-400">Live feed</p>
              <h2 class="text-xl font-semibold text-white">Latest Odoo transactions</h2>
            </div>
            <div class="ml-auto flex items-center gap-2 text-xs text-zinc-400">
              <span class="size-2 animate-pulse rounded-full bg-emerald-400/80"></span> Live
            </div>
          </div>

          <div class="mt-4">
            <div class="grid grid-cols-2 gap-2 rounded-xl border border-white/5 bg-white/5 px-4 py-2 text-[0.7rem] uppercase tracking-[0.35em] text-zinc-400 sm:grid-cols-6">
              <p>e-DOC</p>
              <p>RNC</p>
              <p>Amount</p>
              <p>Tax</p>
              <p>Requested at</p>
              <p class="text-right">Payload</p>
            </div>

            <div
              id="transactions"
              phx-update="stream"
              class="mt-3 divide-y divide-white/5 rounded-2xl border border-white/5 bg-white/5"
            >
              <div class="hidden only:flex flex-col items-center justify-center gap-2 px-6 py-16 text-center text-sm text-zinc-400">
                <.icon name="hero-receipt-percent" class="size-8 text-zinc-500" />
                <p>No transactions yet. Connect your automations to start streaming activity.</p>
              </div>

              <div
                :for={{dom_id, transaction} <- @streams.transactions}
                id={dom_id}
                data-role="transaction-row"
                data-rnc={odoo_value(transaction, :rnc) || ""}
                class="grid grid-cols-1 gap-4 px-4 py-5 transition duration-200 hover:bg-white/5 sm:grid-cols-6"
              >
                <div>
                  <p class="text-xs font-semibold text-white">
                    {odoo_value(transaction, :e_doc) || "—"}
                  </p>
                  <p class="text-[0.7rem] text-zinc-400">ID: {transaction.id}</p>
                </div>

                <div class="text-sm font-medium text-white">
                  {odoo_value(transaction, :rnc) || "—"}
                </div>

                <div class="text-sm font-semibold text-emerald-300">
                  <span data-field="amount">{format_currency(odoo_value(transaction, :amount))}</span>
                </div>

                <div class="text-sm font-semibold text-sky-300">
                  <span data-field="tax">{format_currency(odoo_value(transaction, :tax))}</span>
                </div>

                <div class="text-sm text-zinc-300">
                  {format_timestamp(transaction.odoo_request_at)}
                </div>

                <div class="sm:text-right">
                  <details class="group inline-block w-full rounded-xl border border-white/10 bg-black/50 px-3 py-2 text-left text-xs text-zinc-100 backdrop-blur">
                    <summary class="flex cursor-pointer items-center gap-2 text-[0.65rem] uppercase tracking-[0.4em] text-zinc-400">
                      <.icon
                        name="hero-code-bracket-square"
                        class="size-4 transition group-open:rotate-90"
                      /> Raw JSON
                    </summary>
                    <pre
                      phx-no-curly-interpolation
                      class="mt-2 max-h-52 overflow-x-auto whitespace-pre-wrap rounded-lg bg-zinc-900/80 p-3 text-left font-mono text-[0.7rem] leading-relaxed text-zinc-100"
                    ><%= transaction_payload(transaction) %></pre>
                  </details>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
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

  defp odoo_value(%{odoo_request: request}, key) when is_atom(key) do
    Map.get(request || %{}, key) ||
      Map.get(request || %{}, Atom.to_string(key))
  end

  defp odoo_value(_, _), do: nil

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

  defp transaction_payload(%{odoo_request: nil}), do: "No payload yet"

  defp transaction_payload(%{odoo_request: map}) when is_map(map) do
    Jason.encode!(map, pretty: true)
  end

  defp transaction_payload(%{odoo_request: other}) do
    inspect(other, pretty: true, limit: :infinity)
  end
end
