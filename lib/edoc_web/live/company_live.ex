defmodule EdocWeb.CompanyLive do
  use EdocWeb, :live_view

  alias Edoc.Accounts
  alias Edoc.Accounts.Company
  alias Edoc.OdooAutomationClient, as: Odoo

  @automation_step_labels [
    "Create e-DOC field (Invoice)",
    "Create selection values (Invoice)",
    "Create e-DOC field (Bill)",
    "Create selection values (Bill)",
    "Create inherited view",
    "Create state-change automation"
  ]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      case socket.assigns.live_action do
        :index ->
          companies = Accounts.list_companies(socket.assigns.current_scope)

          socket
          |> assign(:companies_empty?, companies == [])
          |> stream(:companies, companies, reset: true)
          |> assign(:page_title, "Companies")
          |> assign_new(:automation_progress, fn -> %{} end)

        :new ->
          form =
            %Company{}
            |> Accounts.change_company()
            |> to_form()

          socket
          |> assign(:page_title, "New Company")
          |> assign(:form, form)
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"company" => params}, socket) do
    changeset =
      %Company{}
      |> Company.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"company" => params}, socket) do
    case Accounts.create_company(socket.assigns.current_scope, params) do
      {:ok, _company} ->
        {:noreply,
         socket
         |> put_flash(:info, "Company created")
         |> push_navigate(to: ~p"/companies")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Unable to create company")}
    end
  end

  @impl true
  def handle_event("connect", %{"id" => id}, socket) do
    company = Accounts.get_company!(id)
    user_id = socket.assigns.current_scope.user.id

    url = company.odoo_url
    db = company.odoo_db
    user = company.odoo_user
    apikey = company.odoo_apikey

    cond do
      is_nil(url) or url == "" ->
        {:noreply, put_flash(socket, :error, "Missing Odoo URL for #{company.company_name}")}

      is_nil(db) or db == "" ->
        {:noreply, put_flash(socket, :error, "Missing Odoo DB for #{company.company_name}")}

      is_nil(user) or user == "" ->
        {:noreply, put_flash(socket, :error, "Missing Odoo user for #{company.company_name}")}

      is_nil(apikey) or apikey == "" ->
        {:noreply, put_flash(socket, :error, "Missing Odoo API key for #{company.company_name}")}

      true ->
        # Initialize UI progress for this company
        socket =
          assign(
            socket,
            :automation_progress,
            Map.put(socket.assigns.automation_progress, company.id, %{
              current: 0,
              status: :exchanging
            })
          )

        # Kick off async task to run the Odoo setup sequence and stream progress
        parent = self()
        company_id = company.id

        Task.start(fn ->
          try do
            client = Odoo.new(company)
            uid = Odoo.authenticate!(client)

            # Step 1: Create invoice field
            field_id_inv = Odoo.create_edoc_field(client, uid)
            send(parent, {:odoo_automation_progress, company_id, 1})

            # Step 2: Create invoice selection values
            _sel_inv = Odoo.create_edoc_selection_values(client, uid, field_id_inv)
            send(parent, {:odoo_automation_progress, company_id, 2})

            # Step 3: Create bill field
            field_id_bill =
              Odoo.create_edoc_field(
                client,
                uid,
                "x_studio_e_doc_bill",
                "Tipo de e-DOC Gastos",
                "Identificadorde Gastos del tipo de e-DOC requerido para factura electrónica."
              )


            Odoo.create_edoc_field(
                client,
                uid,
                "x_studio_e_doc_bill_seq",
                "Secuencia de e-DOC",
                "e-DOC secuencia factura electrónica.",
                "account.move",
                "text"
              )

            send(parent, {:odoo_automation_progress, company_id, 3})

            # Step 4: Create bill selection values
            _sel_bill = Odoo.create_edoc_selection_values(client, uid, field_id_bill, false)
            send(parent, {:odoo_automation_progress, company_id, 4})

            # Step 5: Create inherited view
            _view_id = Odoo.create_edoc_view_inheritance(client, uid)
            send(parent, {:odoo_automation_progress, company_id, 5})

            # Step 6: Create automation
            _automation_id =
              Odoo.create_state_change_automation(
                client,
                uid,
                "Automation-DGII",
                "Send Webhook Notification (dgii-gw)",
                "account.move",
                user_id,
                company_id,
                "posted"
              )

            send(parent, {:odoo_automation_done, company_id})
          rescue
            e ->
              send(parent, {:odoo_automation_failed, company_id, Exception.message(e)})
          end
        end)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:odoo_automation_progress, company_id, step_index}, socket) do
    # step_index is 1..length(@automation_step_labels)
    socket =
      update(socket, :automation_progress, fn prog ->
        Map.update(prog, company_id, %{current: step_index, status: :exchanging}, fn _ ->
          %{current: step_index, status: :exchanging}
        end)
      end)

    {:noreply, socket}
  end

  def handle_info({:odoo_automation_failed, company_id, reason}, socket) do
    socket =
      update(socket, :automation_progress, fn prog ->
        Map.update(prog, company_id, %{current: 0, status: {:error, reason}}, fn state ->
          Map.put(state, :status, {:error, reason})
        end)
      end)

    {:noreply,
     put_flash(socket, :error, "Odoo automation failed for company #{company_id}: #{reason}")}
  end

  def handle_info({:odoo_automation_done, company_id}, socket) do
    company = Accounts.get_company!(company_id)

    case Accounts.mark_company_connected(socket.assigns.current_scope, company, true) do
      {:ok, updated_company} ->
        socket =
          socket
          |> stream_insert(:companies, updated_company)
          |> update(:automation_progress, fn prog ->
            Map.update(
              prog,
              company_id,
              %{current: length(@automation_step_labels), status: :success},
              fn _ ->
                %{current: length(@automation_step_labels), status: :success}
              end
            )
          end)
          |> put_flash(:info, "Odoo automation completed for #{updated_company.company_name}")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Automation completed, but failed to update status: #{inspect(reason)}"
         )}
    end
  end

  @impl true
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <div class="mx-auto w-full max-w-6xl space-y-5">
        <div id="companies-new-loading" class="pointer-events-none fixed inset-x-0 top-5 z-50 hidden justify-center">
          <div class="inline-flex items-center gap-2 rounded-full border border-indigo-200 bg-indigo-50 px-4 py-2 text-sm font-semibold text-indigo-700 shadow-sm dark:border-indigo-500/40 dark:bg-indigo-500/15 dark:text-indigo-200">
            <.icon name="hero-arrow-path" class="size-4 motion-safe:animate-spin" />
            Opening company form...
          </div>
        </div>

        <.header>
          Companies
          <:subtitle>Create companies, connect Odoo, and monitor automation setup progress.</:subtitle>
          <:actions>
            <.button
              id="companies-new-button"
              navigate={~p"/companies/new"}
              phx-click={
                JS.remove_class("hidden", to: "#companies-new-loading")
                |> JS.add_class("pointer-events-none opacity-70", to: "#companies-new-button")
              }
            >
              <.icon name="hero-plus" class="size-4" /> New Company
            </.button>
          </:actions>
        </.header>

        <div id="companies" phx-update="stream" class="grid grid-cols-1 gap-4">
          <div class="hidden only:block rounded-2xl border border-dashed border-slate-300 bg-white p-10 text-center text-sm text-slate-500 dark:border-slate-700 dark:bg-slate-900/60 dark:text-slate-400">
            No companies yet.
          </div>

          <article
            :for={{id, company} <- @streams.companies}
            id={id}
            class={[
              ui(:card),
              "p-5 transition duration-200 hover:shadow-md dark:hover:border-indigo-500/45"
            ]}
          >
            <div class="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
              <div class="min-w-0 flex-1">
                <div class="flex items-start gap-3">
                  <div class="inline-flex size-12 shrink-0 items-center justify-center rounded-xl bg-indigo-600 text-sm font-semibold text-white shadow-[0_16px_28px_-18px_rgba(79,70,229,0.9)]">
                    {company_initials(company)}
                  </div>
                  <div class="min-w-0">
                    <h2 class="truncate text-lg font-semibold tracking-tight text-slate-900 dark:text-slate-100">
                      {company.company_name}
                    </h2>
                    <p class="text-sm text-slate-500 dark:text-slate-400">RNC: {company.rnc || "—"}</p>

                    <div class="mt-2 flex flex-wrap gap-2">
                      <.status_pill tone={if(company.active, do: "success", else: "neutral")}>
                        {if(company.active, do: "Active", else: "Inactive")}
                      </.status_pill>
                      <.status_pill tone={if(company.connected, do: "success", else: "warning")}>
                        {if(company.connected, do: "Connected", else: "Pending connection")}
                      </.status_pill>
                    </div>
                  </div>
                </div>

                <div class="mt-4 grid gap-2 text-sm text-slate-600 sm:grid-cols-2 dark:text-slate-300">
                  <p class="truncate"><span class="font-semibold">Odoo URL:</span> {company.odoo_url || "—"}</p>
                  <p class="truncate">
                    <span class="font-semibold">Odoo User:</span> {company.odoo_user || "—"}
                  </p>
                </div>

                <% prog = Map.get(@automation_progress, company.id, %{current: 0, status: :idle}) %>
                <div class="mt-4 rounded-xl border border-slate-200 bg-slate-50/80 p-3 dark:border-slate-800 dark:bg-slate-950/40">
                  <ol class="space-y-2">
                    <%= for {label, idx} <- Enum.with_index(automation_step_labels(), 1) do %>
                      <% completed? = prog.current >= idx %>
                      <li class="flex items-start gap-2 text-xs">
                        <span class={[
                          "mt-0.5 inline-flex size-5 items-center justify-center rounded-full border",
                          completed? && "border-emerald-200 bg-emerald-50 text-emerald-600",
                          completed? && "dark:border-emerald-500/40 dark:bg-emerald-500/15 dark:text-emerald-300",
                          !completed? && "border-slate-200 bg-white text-slate-400 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-500"
                        ]}>
                          <.icon name="hero-check" class="size-3.5" />
                        </span>
                        <span class={[
                          completed? && "text-slate-700 dark:text-slate-200",
                          !completed? && "text-slate-500 dark:text-slate-400"
                        ]}>
                          {label}
                        </span>
                      </li>
                    <% end %>
                  </ol>

                  <%= case prog.status do %>
                    <% :exchanging -> %>
                      <p class="mt-3 text-xs font-medium text-slate-600 dark:text-slate-300">
                        Setting up Odoo: step {prog.current} of {length(automation_step_labels())}.
                      </p>
                    <% {:error, reason} -> %>
                      <p class="mt-3 text-xs font-medium text-rose-600 dark:text-rose-300">Error: {reason}</p>
                    <% :success -> %>
                      <p class="mt-3 text-xs font-medium text-emerald-600 dark:text-emerald-300">
                        All setup steps completed.
                      </p>
                    <% _ -> %>
                      <p class="mt-3 text-xs font-medium text-slate-500 dark:text-slate-400">Not started.</p>
                  <% end %>
                </div>
              </div>

              <div class="flex flex-row gap-2 md:flex-col md:items-end">
                <.button variant="secondary" navigate={~p"/companies/#{company.id}/transactions"}>
                  <.icon name="hero-receipt-percent" class="size-4" />
                  Transactions
                </.button>
                <%= unless company.connected or match?(%{status: :success}, @automation_progress[company.id] || %{}) do %>
                  <.button
                    phx-click="connect"
                    phx-value-id={company.id}
                    phx-disable-with="Connecting..."
                    disabled={
                      case @automation_progress[company.id] do
                        %{status: :exchanging} -> true
                        _ -> false
                      end
                    }
                  >
                    Connect
                  </.button>
                <% end %>
              </div>
            </div>
          </article>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp company_initials(%Company{company_name: name}) do
    name
    |> to_string()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  defp automation_step_labels, do: @automation_step_labels

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <div class="mx-auto w-full max-w-3xl space-y-5">
        <.header>
          Create Company
          <:subtitle>Add company details and Odoo credentials to initialize automations.</:subtitle>
        </.header>

        <.surface class="border-indigo-100/70 dark:border-indigo-500/20">
          <.form
            for={@form}
            id="company-form"
            phx-change="validate"
            phx-submit="save"
            class="relative space-y-4 phx-submit-loading:pointer-events-none"
          >
            <div class="hidden items-center justify-center gap-2 rounded-xl border border-indigo-200 bg-indigo-50 px-4 py-2 text-sm font-semibold text-indigo-700 dark:border-indigo-500/40 dark:bg-indigo-500/15 dark:text-indigo-200 phx-submit-loading:flex">
              <.icon name="hero-arrow-path" class="size-4 motion-safe:animate-spin" />
              Creating company, please wait...
            </div>

            <.input
              field={@form[:company_name]}
              type="text"
              label="Company Name"
              placeholder="Acme Corp"
            />
            <.input field={@form[:rnc]} type="text" label="RNC" placeholder="RNC/Tax ID" />

            <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
              <.input
                field={@form[:odoo_url]}
                type="text"
                label="Odoo URL"
                placeholder="https://odoo.example.com"
              />
              <.input field={@form[:odoo_db]} type="text" label="Odoo DB" placeholder="my_db" />
              <.input
                field={@form[:odoo_user]}
                type="text"
                label="Odoo User"
                placeholder="user@example.com"
              />
              <.input field={@form[:odoo_apikey]} type="password" label="Odoo API Key" />
            </div>

            <.input field={@form[:access_token]} type="password" label="Access Token" />

            <div class="flex items-center gap-3 pt-2">
              <.button type="submit" phx-disable-with="Creating company...">
                <span class="phx-submit-loading:hidden">Save company</span>
                <span class="hidden items-center gap-2 phx-submit-loading:inline-flex">
                  <.icon name="hero-arrow-path" class="size-4 motion-safe:animate-spin" />
                  Creating...
                </span>
              </.button>
              <.button navigate={~p"/companies"} variant="ghost">
                Cancel
              </.button>
            </div>
          </.form>
        </.surface>
      </div>
    </Layouts.app>
    """
  end
end
