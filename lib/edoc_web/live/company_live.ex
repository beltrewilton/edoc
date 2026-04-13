defmodule EdocWeb.CompanyLive do
  use EdocWeb, :live_view

  alias Edoc.Accounts
  alias Edoc.Accounts.Company
  alias Edoc.CompanyOnboarding
  alias Edoc.DgiiRncScraper.Result, as: DgiiResult
  alias Edoc.OdooAutomationClient, as: Odoo

  @automation_step_labels [
    "Create e-DOC field (Invoice)",
    "Create selection values (Invoice)",
    "Create e-DOC field (Bill)",
    "Create selection values (Bill)",
    "Create inherited view",
    "Create state-change automation"
  ]
  @secret_fields ~w(access_token odoo_apikey provider_apikey)
  @onboarding_steps [
    %{number: 1, title: "DGII Lookup"},
    %{number: 2, title: "Odoo Validation"},
    %{number: 3, title: "Provider Validation"}
  ]

  @impl true
  def mount(params, _session, socket) do
    socket =
      case socket.assigns.live_action do
        :index ->
          companies = Accounts.list_companies(socket.assigns.current_scope)

          socket
          |> assign(:companies_empty?, companies == [])
          |> assign(:companies, companies)
          |> assign(:page_title, "Companies")
          |> assign_new(:automation_progress, fn -> %{} end)

        :new ->
          assign_new_company_wizard(socket)

        :edit ->
          company = Accounts.get_company_for_scope!(socket.assigns.current_scope, params["id"])
          assign_company_form(socket, company, "Edit Company")
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"company" => params}, %{assigns: %{live_action: :new}} = socket) do
    attrs = merge_onboarding_params(socket, params)
    form = onboarding_form(%Company{}, attrs, socket.assigns.onboarding_step, :validate)

    {:noreply, assign(socket, onboarding_attrs: attrs, form: form)}
  end

  def handle_event("validate", %{"company" => params}, socket) do
    company = current_company(socket)
    attrs = merge_existing_secret_fields(company, params)

    changeset =
      company
      |> Company.changeset(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("lookup_rnc", %{"company" => params}, socket) do
    attrs = merge_onboarding_params(socket, params)
    changeset = Company.onboarding_changeset(%Company{}, attrs, 1) |> Map.put(:action, :validate)

    if changeset.valid? do
      case CompanyOnboarding.lookup_rnc(Map.get(attrs, "rnc", "")) do
        {:ok, %DgiiResult{} = result} ->
          updated_attrs = Map.merge(attrs, mapped_dgii_attrs(result))

          {:noreply,
           socket
           |> assign(:onboarding_step, 2)
           |> assign(:onboarding_attrs, updated_attrs)
           |> assign(:dgii_result, result)
           |> assign(:dgii_lookup_status, validation_state(:success, "DGII company details loaded."))
           |> assign(:odoo_validation, validation_state())
           |> assign(:provider_validation, validation_state())
           |> assign(:form, onboarding_form(%Company{}, updated_attrs, 2))}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:onboarding_step, 1)
           |> assign(:onboarding_attrs, attrs)
           |> assign(:dgii_result, nil)
           |> assign(:dgii_lookup_status, validation_state(:error, dgii_error_message(reason)))
           |> assign(:odoo_validation, validation_state())
           |> assign(:provider_validation, validation_state())
           |> assign(:form, to_form(changeset))}
      end
    else
      {:noreply,
       socket
       |> assign(:onboarding_attrs, attrs)
       |> assign(:dgii_lookup_status, validation_state())
       |> assign(:form, to_form(changeset))}
    end
  end

  def handle_event("change_rnc", _params, socket) do
    attrs =
      socket.assigns.onboarding_attrs
      |> Map.take(["rnc"])
      |> Map.put("rnc", Map.get(socket.assigns.onboarding_attrs, "rnc", ""))

    {:noreply,
     socket
     |> assign(:onboarding_step, 1)
     |> assign(:onboarding_attrs, attrs)
     |> assign(:dgii_result, nil)
     |> assign(:dgii_lookup_status, validation_state())
     |> assign(:odoo_validation, validation_state())
     |> assign(:provider_validation, validation_state())
     |> assign(:form, onboarding_form(%Company{}, attrs, 1))}
  end

  def handle_event("validate_odoo", %{"company" => params}, socket) do
    attrs = merge_onboarding_params(socket, params)
    changeset = Company.onboarding_changeset(%Company{}, attrs, 2) |> Map.put(:action, :validate)

    if changeset.valid? do
      case CompanyOnboarding.validate_odoo(attrs) do
        {:ok, result} ->
          {:noreply,
           socket
           |> assign(:onboarding_step, 3)
           |> assign(:onboarding_attrs, attrs)
           |> assign(:odoo_validation, validation_state(:success, Map.get(result, :message)))
           |> assign(:provider_validation, validation_state())
           |> assign(:form, onboarding_form(%Company{}, attrs, 3))}

        {:error, message} ->
          {:noreply,
           socket
           |> assign(:onboarding_attrs, attrs)
           |> assign(:odoo_validation, validation_state(:error, message))
           |> assign(:form, to_form(changeset))}
      end
    else
      {:noreply,
       socket
       |> assign(:onboarding_attrs, attrs)
       |> assign(:odoo_validation, validation_state())
       |> assign(:form, to_form(changeset))}
    end
  end

  def handle_event("edit_odoo", _params, socket) do
    attrs = socket.assigns.onboarding_attrs

    {:noreply,
     socket
     |> assign(:onboarding_step, 2)
     |> assign(:odoo_validation, validation_state())
     |> assign(:provider_validation, validation_state())
     |> assign(:form, onboarding_form(%Company{}, attrs, 2))}
  end

  def handle_event("validate_provider", %{"company" => params}, socket) do
    attrs = merge_onboarding_params(socket, params)
    changeset = Company.onboarding_changeset(%Company{}, attrs, 3) |> Map.put(:action, :validate)

    if changeset.valid? do
      case CompanyOnboarding.validate_provider(attrs) do
        {:ok, result} ->
          socket
          |> assign(:onboarding_attrs, attrs)
          |> assign(:provider_validation, validation_state(:success, Map.get(result, :message)))
          |> create_company(attrs)

        {:error, message} ->
          {:noreply,
           socket
           |> assign(:onboarding_attrs, attrs)
           |> assign(:provider_validation, validation_state(:error, message))
           |> assign(:form, to_form(changeset))}
      end
    else
      {:noreply,
       socket
       |> assign(:onboarding_attrs, attrs)
       |> assign(:provider_validation, validation_state())
       |> assign(:form, to_form(changeset))}
    end
  end

  def handle_event("save", %{"company" => params}, socket) do
    update_company(socket, params)
  end

  @impl true
  def handle_event("connect", %{"id" => id}, socket) do
    company = Accounts.get_company_for_scope!(socket.assigns.current_scope, id)
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
        socket =
          assign(
            socket,
            :automation_progress,
            Map.put(socket.assigns.automation_progress, company.id, %{
              current: 0,
              status: :exchanging
            })
          )

        parent = self()
        company_id = company.id
        company_name = company.company_name

        Task.start(fn ->
          try do
            client = Odoo.new(company)
            uid = Odoo.authenticate!(client)

            # Create the invoice e-DOC field in Odoo.
            field_id_inv = Odoo.create_edoc_field(client, uid)
            send(parent, {:odoo_automation_progress, company_id, 1})

            # Create the invoice e-DOC selection values in Odoo.
            _sel_inv = Odoo.create_edoc_selection_values(client, uid, field_id_inv)
            send(parent, {:odoo_automation_progress, company_id, 2})

            # Create the bill e-DOC field in Odoo.
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

            # Create the bill e-DOC selection values in Odoo.
            _sel_bill = Odoo.create_edoc_selection_values(client, uid, field_id_bill, false)
            send(parent, {:odoo_automation_progress, company_id, 4})

            # Create the inherited view in Odoo.
            _view_id = Odoo.create_edoc_view_inheritance(client, uid)
            send(parent, {:odoo_automation_progress, company_id, 5})

            # Create the state-change automation in Odoo.
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

            send(parent, {:odoo_automation_progress, company_id, 6})

            # Wait briefly so the UI can show every step completed before the final flash arrives.
            Process.sleep(350)
            send(parent, {:odoo_automation_done, company_id, company_name})
          rescue
            error ->
              send(parent, {:odoo_automation_failed, company_id, Exception.message(error)})
          end
        end)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:odoo_automation_progress, company_id, step_index}, socket) do
    status =
      if step_index >= length(@automation_step_labels), do: :finalizing, else: :exchanging

    socket =
      update(socket, :automation_progress, fn prog ->
        Map.update(prog, company_id, %{current: step_index, status: status}, fn _ ->
          %{current: step_index, status: status}
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
     put_flash(socket, :error, "Odoo plugin installation failed for company #{company_id}: #{reason}")}
  end

  def handle_info({:odoo_automation_done, company_id, company_name}, socket) do
    company = Accounts.get_company!(company_id)

    case Accounts.mark_company_connected(socket.assigns.current_scope, company, true) do
      {:ok, updated_company} ->
        socket =
          socket
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
          |> update(:companies, fn companies ->
            Enum.map(companies, fn
              %{id: ^company_id} -> updated_company
              other -> other
            end)
          end)
          |> put_flash(:info, "Odoo plugin installation completed for #{company_name}")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Odoo plugin installation completed, but persisting status failed: #{inspect(reason)}"
         )}
    end
  end

  @impl true
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <div class="mx-auto w-full max-w-6xl space-y-5">
        <div
          id="companies-new-loading"
          class="pointer-events-none fixed inset-x-0 top-5 z-50 hidden justify-center"
        >
          <div class="inline-flex items-center gap-2 rounded-full border border-indigo-200 bg-indigo-50 px-4 py-2 text-sm font-semibold text-indigo-700 shadow-sm dark:border-indigo-500/40 dark:bg-indigo-500/15 dark:text-indigo-200">
            <.icon name="hero-arrow-path" class="size-4 motion-safe:animate-spin" />
            Opening company form...
          </div>
        </div>

        <.header>
          Companies
          <:subtitle>Create companies, connect Odoo, and manage provider credentials.</:subtitle>
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

        <div id="companies" class="grid grid-cols-1 gap-4">
          <div
            id="companies-empty-state"
            class="hidden only:block rounded-2xl border border-dashed border-slate-300 bg-white p-10 text-center text-sm text-slate-500 dark:border-slate-700 dark:bg-slate-900/60 dark:text-slate-400"
          >
            No companies yet.
          </div>

          <article
            :for={company <- @companies}
            id={company.id}
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
                    <p class="text-sm text-slate-500 dark:text-slate-400">
                      RNC: {company.rnc || "—"}
                    </p>

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
                  <p class="truncate">
                    <span class="font-semibold">Odoo URL:</span> {company.odoo_url || "—"}
                  </p>
                  <p class="truncate">
                    <span class="font-semibold">Odoo User:</span> {company.odoo_user || "—"}
                  </p>
                  <p class="truncate">
                    <span class="font-semibold">Provider Endpoint:</span> {company.provider_endpoint ||
                      "—"}
                  </p>
                  <p class="truncate">
                    <span class="font-semibold">Provider API Key:</span> {provider_key_status(company)}
                  </p>
                </div>

                <% prog = Map.get(@automation_progress, company.id, %{current: 0, status: :idle}) %>
                <% install_success? = prog.status == :success %>
                <% install_loading? = prog.status in [:exchanging, :finalizing] %>
                <% active_step = if prog.status == :exchanging, do: min(prog.current + 1, length(automation_step_labels())), else: nil %>
                <div class="mt-4 rounded-xl border border-slate-200 bg-slate-50/80 p-3 dark:border-slate-800 dark:bg-slate-950/40">
                  <ol class="space-y-2">
                    <%= for {label, idx} <- Enum.with_index(automation_step_labels(), 1) do %>
                      <% completed? = prog.current >= idx %>
                      <% active? = active_step == idx %>
                      <li class="flex items-start gap-2 text-xs">
                        <span class={[
                          "mt-0.5 inline-flex size-5 items-center justify-center rounded-full border",
                          completed? && "border-emerald-200 bg-emerald-50 text-emerald-600",
                          completed? &&
                            "dark:border-emerald-500/40 dark:bg-emerald-500/15 dark:text-emerald-300",
                          active? && "border-indigo-200 bg-indigo-50 text-indigo-600",
                          active? &&
                            "dark:border-indigo-500/40 dark:bg-indigo-500/15 dark:text-indigo-300",
                          !completed? &&
                            !active? &&
                            "border-slate-200 bg-white text-slate-400 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-500"
                        ]}>
                          <%= cond do %>
                            <% completed? -> %>
                              <.icon name="hero-check" class="size-3.5 text-emerald-600 dark:text-emerald-300" />
                            <% active? -> %>
                              <.icon name="hero-arrow-path" class="size-3.5 animate-spin" />
                            <% true -> %>
                              <.icon name="hero-ellipsis-horizontal" class="size-3.5" />
                          <% end %>
                        </span>
                        <span class={[
                          completed? && "text-slate-700 dark:text-slate-200",
                          active? && "text-indigo-700 dark:text-indigo-200",
                          !completed? && !active? && "text-slate-500 dark:text-slate-400"
                        ]}>
                          {label}
                        </span>
                      </li>
                    <% end %>
                  </ol>

                  <%= case prog.status do %>
                    <% :exchanging -> %>
                      <p class="mt-3 text-xs font-medium text-slate-600 dark:text-slate-300">
                        Installing Odoo plugin: step {min(prog.current + 1, length(automation_step_labels()))} of {length(automation_step_labels())}.
                      </p>
                    <% :finalizing -> %>
                      <p class="mt-3 text-xs font-medium text-slate-600 dark:text-slate-300">
                        Finalizing Odoo plugin installation...
                      </p>
                    <% {:error, reason} -> %>
                      <p class="mt-3 text-xs font-medium text-rose-600 dark:text-rose-300">
                        Error: {reason}
                      </p>
                    <% :success -> %>
                      <p class="mt-3 text-xs font-medium text-emerald-600 dark:text-emerald-300">
                        Plugin installation completed successfully.
                      </p>
                    <% _ -> %>
                      <p class="mt-3 text-xs font-medium text-slate-500 dark:text-slate-400">
                        Not started.
                      </p>
                  <% end %>
                </div>
              </div>

                <div class="flex flex-row flex-wrap gap-2 md:flex-col md:items-end">
                  <.button variant="secondary" navigate={~p"/companies/#{company.id}/edit"}>
                    <.icon name="hero-pencil-square" class="size-4" /> Edit
                  </.button>
                  <.button variant="secondary" navigate={~p"/companies/#{company.id}/transactions"}>
                    <.icon name="hero-receipt-percent" class="size-4" /> Transactions
                  </.button>
                  <%= unless company.connected or install_success? do %>
                    <.button
                      phx-click="connect"
                      phx-value-id={company.id}
                      phx-disable-with="Installing Odoo Plugin..."
                      class="cursor-pointer"
                      disabled={install_loading?}
                    >
                      <%= if install_loading? do %>
                        <.icon name="hero-arrow-path" class="size-4 animate-spin" />
                      <% else %>
                        <.icon name="hero-arrow-down-tray" class="size-4" />
                      <% end %>
                      Install Odoo Plugin
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

  def render(%{live_action: :new} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <div class="mx-auto w-full max-w-4xl space-y-5">
        <.header>
          Create Company
          <:subtitle>
            Validate the company progressively: DGII first, Odoo second, provider last.
          </:subtitle>
        </.header>

        <.surface class="overflow-hidden border-indigo-100/70 dark:border-indigo-500/20">
          <div class="space-y-6">
            <div class="grid gap-3 md:grid-cols-3">
              <%= for step <- onboarding_steps() do %>
                <div class={[
                  "rounded-2xl border px-4 py-4 transition",
                  @onboarding_step > step.number &&
                    "border-emerald-200 bg-emerald-50/80 dark:border-emerald-500/30 dark:bg-emerald-500/10",
                  @onboarding_step == step.number &&
                    "border-indigo-200 bg-indigo-50/80 dark:border-indigo-500/30 dark:bg-indigo-500/10",
                  @onboarding_step < step.number &&
                    "border-slate-200 bg-slate-50/70 dark:border-slate-800 dark:bg-slate-900/60"
                ]}>
                  <div class="flex items-center gap-3">
                    <span class={[
                      "inline-flex size-9 items-center justify-center rounded-full text-sm font-semibold",
                      @onboarding_step > step.number &&
                        "bg-emerald-600 text-white dark:bg-emerald-500",
                      @onboarding_step == step.number &&
                        "bg-indigo-600 text-white dark:bg-indigo-500",
                      @onboarding_step < step.number &&
                        "bg-slate-200 text-slate-600 dark:bg-slate-800 dark:text-slate-300"
                    ]}>
                      <%= if @onboarding_step > step.number do %>
                        <.icon name="hero-check" class="size-4" />
                      <% else %>
                        {step.number}
                      <% end %>
                    </span>
                    <div>
                      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500 dark:text-slate-400">
                        Step {step.number}
                      </p>
                      <p class="text-sm font-semibold text-slate-900 dark:text-slate-100">
                        {step.title}
                      </p>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>

            <%= if @onboarding_step == 1 do %>
              <.form
                for={@form}
                id="company-step-1-form"
                phx-change="validate"
                phx-submit="lookup_rnc"
                class="space-y-5"
              >
                <div class="rounded-3xl bg-[radial-gradient(circle_at_top_left,_rgba(79,70,229,0.12),_transparent_48%),linear-gradient(135deg,rgba(255,255,255,1),rgba(244,247,255,1))] p-6 dark:bg-[radial-gradient(circle_at_top_left,_rgba(99,102,241,0.18),_transparent_48%),linear-gradient(135deg,rgba(15,23,42,0.98),rgba(15,23,42,0.9))]">
                  <div class="max-w-2xl space-y-2">
                    <p class="text-xs font-semibold uppercase tracking-[0.28em] text-indigo-600 dark:text-indigo-300">
                      DGII source of truth
                    </p>
                    <h2 class="text-2xl font-semibold tracking-tight text-slate-900 dark:text-slate-100">
                      Search the company by RNC before anything else.
                    </h2>
                    <p class="text-sm text-slate-600 dark:text-slate-300">
                      The RNC field only accepts numbers. The form will stay locked on this step until the DGII lookup succeeds.
                    </p>
                  </div>
                </div>

                <div class="grid gap-5 md:grid-cols-[minmax(0,1fr)_auto] md:items-end">
                  <.input
                    field={@form[:rnc]}
                    type="text"
                    label="RNC"
                    placeholder="132190068"
                    inputmode="numeric"
                    pattern="[0-9]*"
                    maxlength="11"
                    autocomplete="off"
                  />

                  <.button
                    id="company-rnc-lookup-button"
                    type="submit"
                    phx-disable-with="Looking up..."
                    class="w-full justify-center md:w-auto"
                  >
                    <.icon name="hero-magnifying-glass" class="size-4" /> Lookup DGII
                  </.button>
                </div>

                <.validation_notice status={@dgii_lookup_status} idle_message="Ready to search DGII." />

                <div class="flex items-center gap-3 pt-2">
                  <.button navigate={~p"/companies"} variant="ghost">
                    Cancel
                  </.button>
                </div>
              </.form>
            <% end %>

            <%= if @onboarding_step == 2 do %>
              <.form
                for={@form}
                id="company-step-2-form"
                phx-change="validate"
                phx-submit="validate_odoo"
                class="space-y-6"
              >
                <div class="flex flex-col gap-4 rounded-3xl border border-slate-200 bg-slate-50/80 p-6 dark:border-slate-800 dark:bg-slate-900/70">
                  <div class="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
                    <div>
                      <p class="text-xs font-semibold uppercase tracking-[0.28em] text-indigo-600 dark:text-indigo-300">
                        Step 2
                      </p>
                      <h2 class="mt-2 text-xl font-semibold tracking-tight text-slate-900 dark:text-slate-100">
                        Confirm DGII details and validate Odoo.
                      </h2>
                    </div>
                    <.button
                      id="company-change-rnc-button"
                      type="button"
                      variant="ghost"
                      phx-click="change_rnc"
                    >
                      Change RNC
                    </.button>
                  </div>

                  <div class="grid gap-3 md:grid-cols-2">
                    <.dgii_detail label="DGII tax ID" value={@dgii_result && @dgii_result.tax_id} />
                    <.dgii_detail
                      label="Legal name"
                      value={@dgii_result && @dgii_result.legal_name}
                    />
                    <.dgii_detail
                      label="Economic activity"
                      value={@dgii_result && @dgii_result.economic_activity}
                    />
                    <.dgii_detail
                      label="Local administration"
                      value={@dgii_result && @dgii_result.local_administration}
                    />
                  </div>
                </div>

                <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
                  <.input
                    field={@form[:company_name]}
                    type="text"
                    label="Mapped Company Name"
                    readonly
                  />
                  <.input field={@form[:rnc]} type="text" label="Mapped RNC" readonly />
                  <.input
                    field={@form[:economic_activity]}
                    type="text"
                    label="Mapped Economic Activity"
                    readonly
                  />
                  <.input
                    field={@form[:local_administration]}
                    type="text"
                    label="Mapped Local Administration"
                    readonly
                  />
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
                  <.input
                    field={@form[:odoo_apikey]}
                    type="password"
                    label="Odoo API Key"
                    placeholder="Enter API key"
                  />
                </div>

                <.validation_notice
                  status={@odoo_validation}
                  idle_message="Enter the Odoo credentials and validate the connection."
                />

                <div class="flex items-center gap-3 pt-2">
                  <.button
                    id="company-odoo-validate-button"
                    type="submit"
                    phx-disable-with="Validating Odoo..."
                  >
                    <.icon name="hero-cloud-arrow-up" class="size-4" />
                    {validation_button_label(@odoo_validation, "Validate Odoo", "Retry Odoo validation")}
                  </.button>
                  <.button navigate={~p"/companies"} variant="ghost">
                    Cancel
                  </.button>
                </div>
              </.form>
            <% end %>

            <%= if @onboarding_step == 3 do %>
              <.form
                for={@form}
                id="company-step-3-form"
                phx-change="validate"
                phx-submit="validate_provider"
                class="space-y-6"
              >
                <input type="hidden" name="company[rnc]" value={input_value(@form[:rnc])} />
                <input
                  type="hidden"
                  name="company[company_name]"
                  value={input_value(@form[:company_name])}
                />
                <input
                  type="hidden"
                  name="company[economic_activity]"
                  value={input_value(@form[:economic_activity])}
                />
                <input
                  type="hidden"
                  name="company[local_administration]"
                  value={input_value(@form[:local_administration])}
                />
                <input
                  type="hidden"
                  name="company[odoo_url]"
                  value={input_value(@form[:odoo_url])}
                />
                <input
                  type="hidden"
                  name="company[odoo_db]"
                  value={input_value(@form[:odoo_db])}
                />
                <input
                  type="hidden"
                  name="company[odoo_user]"
                  value={input_value(@form[:odoo_user])}
                />
                <input
                  type="hidden"
                  name="company[odoo_apikey]"
                  value={input_value(@form[:odoo_apikey])}
                />

                <div class="grid gap-6 lg:grid-cols-[minmax(0,1.2fr)_minmax(0,0.8fr)]">
                  <div class="space-y-6">
                    <div class="rounded-3xl border border-slate-200 bg-slate-50/80 p-6 dark:border-slate-800 dark:bg-slate-900/70">
                      <div class="flex items-start justify-between gap-4">
                        <div>
                          <p class="text-xs font-semibold uppercase tracking-[0.28em] text-indigo-600 dark:text-indigo-300">
                            Step 3
                          </p>
                          <h2 class="mt-2 text-xl font-semibold tracking-tight text-slate-900 dark:text-slate-100">
                            Validate the provider and persist the company.
                          </h2>
                        </div>
                        <.button
                          id="company-edit-odoo-button"
                          type="button"
                          variant="ghost"
                          phx-click="edit_odoo"
                        >
                          Edit Odoo
                        </.button>
                      </div>
                    </div>

                    <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
                      <.input
                        field={@form[:provider_endpoint]}
                        type="text"
                        label="Provider Endpoint"
                        placeholder="https://sandbox.e-taxcore.com/api/v2/e-docs"
                      />
                      <.input
                        field={@form[:provider_apikey]}
                        type="password"
                        label="Provider API Key"
                        placeholder="Enter provider API key"
                      />
                    </div>

                    <.validation_notice
                      status={@provider_validation}
                      idle_message="The company will be created only after the provider validation succeeds."
                    />

                    <div class="flex items-center gap-3 pt-2">
                      <.button
                        id="company-provider-validate-button"
                        type="submit"
                        phx-disable-with="Validating provider..."
                      >
                        <.icon name="hero-shield-check" class="size-4" />
                        {validation_button_label(
                          @provider_validation,
                          "Validate provider and save",
                          "Retry provider validation"
                        )}
                      </.button>
                      <.button navigate={~p"/companies"} variant="ghost">
                        Cancel
                      </.button>
                    </div>
                  </div>

                  <div class="space-y-4">
                    <.surface>
                      <p class="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                        DGII details
                      </p>
                      <dl class="mt-4 space-y-3 text-sm">
                        <div>
                          <dt class="font-semibold text-slate-700 dark:text-slate-200">Tax ID</dt>
                          <dd class="text-slate-600 dark:text-slate-300">
                            {@dgii_result && @dgii_result.tax_id}
                          </dd>
                        </div>
                        <div>
                          <dt class="font-semibold text-slate-700 dark:text-slate-200">Legal name</dt>
                          <dd class="text-slate-600 dark:text-slate-300">
                            {@dgii_result && @dgii_result.legal_name}
                          </dd>
                        </div>
                      </dl>
                    </.surface>

                    <.surface>
                      <p class="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                        Odoo validation
                      </p>
                      <dl class="mt-4 space-y-3 text-sm">
                        <div>
                          <dt class="font-semibold text-slate-700 dark:text-slate-200">Odoo URL</dt>
                          <dd class="text-slate-600 dark:text-slate-300">
                            {input_value(@form[:odoo_url])}
                          </dd>
                        </div>
                        <div>
                          <dt class="font-semibold text-slate-700 dark:text-slate-200">Odoo DB</dt>
                          <dd class="text-slate-600 dark:text-slate-300">
                            {input_value(@form[:odoo_db])}
                          </dd>
                        </div>
                        <div>
                          <dt class="font-semibold text-slate-700 dark:text-slate-200">Odoo user</dt>
                          <dd class="text-slate-600 dark:text-slate-300">
                            {input_value(@form[:odoo_user])}
                          </dd>
                        </div>
                      </dl>
                    </.surface>
                  </div>
                </div>
              </.form>
            <% end %>
          </div>
        </.surface>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <div class="mx-auto w-full max-w-3xl space-y-5">
        <.header>
          {company_form_title(@live_action)}
          <:subtitle>{company_form_subtitle(@live_action)}</:subtitle>
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
              {company_submit_loading_label(@live_action)}
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
                field={@form[:provider_endpoint]}
                type="text"
                label="Provider Endpoint"
                placeholder="https://sandbox.e-taxcore.com/api/v2/e-docs"
              />
              <.input
                field={@form[:provider_apikey]}
                type="password"
                label="Provider API Key"
                placeholder={secret_placeholder(@live_action)}
              />
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
              <.input
                field={@form[:odoo_apikey]}
                type="password"
                label="Odoo API Key"
                placeholder={secret_placeholder(@live_action)}
              />
            </div>

            <.input
              field={@form[:access_token]}
              type="password"
              label="Access Token"
              placeholder={secret_placeholder(@live_action)}
            />

            <div class="flex items-center gap-3 pt-2">
              <.button type="submit" phx-disable-with={company_submit_loading_label(@live_action)}>
                <span class="phx-submit-loading:hidden">{company_submit_label(@live_action)}</span>
                <span class="hidden items-center gap-2 phx-submit-loading:inline-flex">
                  <.icon name="hero-arrow-path" class="size-4 motion-safe:animate-spin" />
                  {company_submit_loading_short_label(@live_action)}
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

  attr :status, :map, required: true
  attr :idle_message, :string, required: true

  defp validation_notice(assigns) do
    tone =
      case assigns.status.state do
        :success -> "success"
        :error -> "danger"
        _ -> "neutral"
      end

    message = assigns.status.message || assigns.idle_message

    assigns = assign(assigns, tone: tone, message: message)

    ~H"""
    <div class={[
      "rounded-2xl border px-4 py-3 text-sm",
      @tone == "success" &&
        "border-emerald-200 bg-emerald-50 text-emerald-700 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-200",
      @tone == "danger" &&
        "border-rose-200 bg-rose-50 text-rose-700 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-200",
      @tone == "neutral" &&
        "border-slate-200 bg-slate-50 text-slate-600 dark:border-slate-800 dark:bg-slate-900/60 dark:text-slate-300"
    ]}>
      <div class="flex items-center gap-2">
        <.icon
          name={
            case @status.state do
              :success -> "hero-check-circle"
              :error -> "hero-exclamation-triangle"
              _ -> "hero-information-circle"
            end
          }
          class="size-5 shrink-0"
        />
        <p>{@message}</p>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, default: nil

  defp dgii_detail(assigns) do
    ~H"""
    <div class="rounded-2xl border border-white/60 bg-white/80 px-4 py-3 shadow-sm dark:border-slate-800 dark:bg-slate-950/60">
      <p class="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500 dark:text-slate-400">
        {@label}
      </p>
      <p class="mt-2 text-sm font-medium text-slate-900 dark:text-slate-100">{@value}</p>
    </div>
    """
  end

  defp create_company(socket, params) do
    case Accounts.create_company(socket.assigns.current_scope, params) do
      {:ok, _company} ->
        {:noreply,
         socket
         |> put_flash(:info, "Company created")
         |> push_navigate(to: ~p"/companies")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:company, %Company{})
         |> assign(:form, to_form(changeset))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Unable to create company")}
    end
  end

  defp update_company(socket, params) do
    company = current_company(socket)
    attrs = merge_existing_secret_fields(company, params)

    case Accounts.update_company(socket.assigns.current_scope, company, attrs) do
      {:ok, _company} ->
        {:noreply,
         socket
         |> put_flash(:info, "Company updated")
         |> push_navigate(to: ~p"/companies")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:company, company)
         |> assign(:form, to_form(changeset))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Unable to update company")}
    end
  end

  defp assign_new_company_wizard(socket) do
    attrs = %{"rnc" => ""}

    socket
    |> assign(:page_title, "New Company")
    |> assign(:company, %Company{})
    |> assign(:onboarding_step, 1)
    |> assign(:onboarding_attrs, attrs)
    |> assign(:dgii_result, nil)
    |> assign(:dgii_lookup_status, validation_state())
    |> assign(:odoo_validation, validation_state())
    |> assign(:provider_validation, validation_state())
    |> assign(:form, onboarding_form(%Company{}, attrs, 1))
  end

  defp assign_company_form(socket, %Company{} = company, page_title) do
    form =
      company
      |> Accounts.change_company()
      |> to_form()

    socket
    |> assign(:page_title, page_title)
    |> assign(:company, company)
    |> assign(:form, form)
  end

  defp onboarding_form(company, attrs, step, action \\ nil) do
    changeset = Company.onboarding_changeset(company, attrs, step)
    changeset = if action, do: Map.put(changeset, :action, action), else: changeset
    to_form(changeset)
  end

  defp merge_onboarding_params(socket, params) do
    socket.assigns.onboarding_attrs
    |> Map.merge(normalize_onboarding_params(params))
  end

  defp normalize_onboarding_params(params) when is_map(params) do
    params
    |> Enum.into(%{}, fn
      {key, value} when is_binary(value) -> {key, String.trim(value)}
      {key, value} -> {key, value}
    end)
    |> Map.update("rnc", "", &sanitize_rnc/1)
  end

  defp mapped_dgii_attrs(%DgiiResult{} = result) do
    %{
      "rnc" => sanitize_rnc(result.tax_id),
      "company_name" => result.legal_name,
      "economic_activity" => result.economic_activity,
      "local_administration" => result.local_administration
    }
  end

  defp validation_state(state \\ :idle, message \\ nil) do
    %{state: state, message: message}
  end

  defp dgii_error_message(:blank_identifier), do: "Enter a valid numeric RNC before searching."
  defp dgii_error_message(:result_not_found), do: "DGII did not return a company for that RNC."
  defp dgii_error_message(:search_form_not_found), do: "DGII lookup is unavailable right now. Retry."

  defp dgii_error_message({:http_error, status, _body}),
    do: "DGII returned HTTP #{status}. Retry in a moment."

  defp dgii_error_message(reason), do: "DGII lookup failed: #{inspect(reason)}"

  defp sanitize_rnc(value) when is_binary(value), do: String.replace(value, ~r/\D/, "")
  defp sanitize_rnc(_value), do: ""

  defp input_value(field) do
    field.value
  end

  defp validation_button_label(%{state: :error}, _default, retry_label), do: retry_label
  defp validation_button_label(_status, default_label, _retry_label), do: default_label

  defp current_company(socket) do
    Map.get(socket.assigns, :company, %Company{})
  end

  defp merge_existing_secret_fields(%Company{id: nil}, params), do: params

  defp merge_existing_secret_fields(%Company{} = company, params) when is_map(params) do
    Enum.reduce(@secret_fields, params, fn field, acc ->
      case Map.get(acc, field) do
        value when value in [nil, ""] ->
          existing_value = Map.get(company, String.to_existing_atom(field))

          if is_binary(existing_value) and byte_size(existing_value) > 0 do
            Map.put(acc, field, existing_value)
          else
            acc
          end

        _value ->
          acc
      end
    end)
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

  defp provider_key_status(%Company{provider_apikey: value})
       when is_binary(value) and byte_size(value) > 0,
       do: "Configured"

  defp provider_key_status(_company), do: "Missing"

  defp company_form_title(:edit), do: "Edit Company"
  defp company_form_title(_live_action), do: "Create Company"

  defp company_form_subtitle(:edit),
    do: "Update company details plus Odoo and provider credentials."

  defp company_form_subtitle(_live_action),
    do: "Add company details plus Odoo and provider credentials to initialize automations."

  defp company_submit_label(:edit), do: "Update company"
  defp company_submit_label(_live_action), do: "Save company"

  defp company_submit_loading_label(:edit), do: "Updating company, please wait..."
  defp company_submit_loading_label(_live_action), do: "Creating company, please wait..."

  defp company_submit_loading_short_label(:edit), do: "Updating..."
  defp company_submit_loading_short_label(_live_action), do: "Creating..."

  defp secret_placeholder(:edit), do: "Leave blank to keep current value"
  defp secret_placeholder(_live_action), do: nil

  defp automation_step_labels, do: @automation_step_labels
  defp onboarding_steps, do: @onboarding_steps
end
