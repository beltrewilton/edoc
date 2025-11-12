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
          assign(socket, :automation_progress,
            Map.put(socket.assigns.automation_progress, company.id, %{current: 0, status: :exchanging})
          )

        # Kick off async task to run the Odoo setup sequence and stream progress
        parent = self()
        company_id = company.id
        company_name = company.company_name

        Task.start(fn ->
          try do
            client = Odoo.new(url, db, user, apikey)
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
            Map.update(prog, company_id, %{current: length(@automation_step_labels), status: :success}, fn _ ->
              %{current: length(@automation_step_labels), status: :success}
            end)
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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-5xl mx-auto px-4 py-6">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-semibold">Companies</h1>
          <.button navigate={~p"/companies/new"} variant="primary">New Company</.button>
        </div>

        <div id="companies" phx-update="stream" class="grid grid-cols-1 gap-4">
          <div class="hidden only:block col-span-full text-center text-sm text-zinc-600">No companies yet</div>

          <.card :for={{id, company} <- @streams.companies} id={id} class="bg-base-100 w-full shadow-xl">
            <:card_title class="text-base">{company.company_name}</:card_title>
            <:card_body>
              <div class="flex items-start gap-3">
                <.avatar placeholder online={company.connected}>
                  <div class="w-12 rounded-full bg-neutral text-neutral-content">
                    <span class="text-lg">{company_initials(company)}</span>
                  </div>
                </.avatar>
                <div class="flex-1">
                  <p class="text-xs text-zinc-500">RNC: {company.rnc || "—"}</p>

                  <div class="mt-2 flex flex-wrap gap-2">
                    <span class={["badge badge-sm", company.active && "badge-success", !company.active && "badge-ghost"]}>Active</span>
                    <span class={["badge badge-sm", company.connected && "badge-success", !company.connected && "badge-ghost"]}>Connected</span>
                  </div>

                  <div class="mt-3 text-xs space-y-1">
                    <div class="truncate"><span class="font-medium">Odoo URL:</span> {company.odoo_url || "—"}</div>
                    <div class="truncate"><span class="font-medium">Odoo User:</span> {company.odoo_user || "—"}</div>
                  </div>
                  <% prog = Map.get(@automation_progress, company.id, %{current: 0, status: :idle}) %>
                  <div class="mt-4">
                    <ul class="timeline overflow-x-auto text-xs">
                      <%= for {label, idx} <- Enum.with_index(automation_step_labels(), 1) do %>
                        <% completed? = prog.current >= idx %>
                        <li>
                          <hr :if={idx > 1} class={[completed? && "bg-primary"]} />
                          <div :if={rem(idx, 2) == 1} class="timeline-start timeline-box text-xs p-2 max-w-[12rem] sm:max-w-[16rem] break-words">{label}</div>
                          <div class="timeline-middle">
                            <.icon name="hero-check-circle" class={["h-4 w-4 sm:h-5 sm:w-5", completed? && "text-primary", !completed? && "text-base-content/40"]} />
                          </div>
                          <div :if={rem(idx, 2) == 0} class="timeline-end timeline-box text-xs p-2 max-w-[12rem] sm:max-w-[16rem] break-words">{label}</div>
                          <hr class={[completed? && "bg-primary"]} />
                        </li>
                      <% end %>
                    </ul>
                    <%= case prog.status do %>
                      <% :exchanging -> %>
                        <p class="mt-2 text-xs text-zinc-500">Setting up Odoo: step {prog.current} of {length(automation_step_labels())}...</p>
                      <% {:error, reason} -> %>
                        <p class="mt-2 text-xs text-red-600">Error: {reason}</p>
                      <% :success -> %>
                        <p class="mt-2 text-xs text-emerald-600">All steps completed.</p>
                      <% _ -> %>
                        <p class="mt-2 text-xs text-zinc-500">Not started.</p>
                    <% end %>
                  </div>
                </div>
              </div>

            </:card_body>
            <:card_actions class="justify-end mt-2">
              <%= unless company.connected or match?(%{status: :success}, @automation_progress[company.id] || %{}) do %>
                <.button
                  color="primary"
                  phx-click="connect"
                  phx-value-id={company.id}
                  phx-disable-with="Connecting..."
                  disabled={case @automation_progress[company.id] do %{status: :exchanging} -> true; _ -> false end}
                >
                  Connect
                </.button>
              <% end %>
            </:card_actions>
          </.card>
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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-2xl mx-auto px-4 py-6">
        <h1 class="text-2xl font-semibold mb-6">Create Company</h1>

        <.form for={@form} id="company-form" phx-change="validate" phx-submit="save" class="space-y-4">
          <.input field={@form[:company_name]} type="text" label="Company Name" placeholder="Acme Corp" />
          <.input field={@form[:rnc]} type="text" label="RNC" placeholder="RNC/Tax ID" />

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.input field={@form[:odoo_url]} type="text" label="Odoo URL" placeholder="https://odoo.example.com" />
            <.input field={@form[:odoo_db]} type="text" label="Odoo DB" placeholder="my_db" />
            <.input field={@form[:odoo_user]} type="text" label="Odoo User" placeholder="user@example.com" />
            <.input field={@form[:odoo_apikey]} type="password" label="Odoo API Key" />
          </div>

          <.input field={@form[:access_token]} type="password" label="Access Token" />

          <div class="flex items-center gap-3 pt-2">
            <.button type="submit">Save</.button>
            <.link navigate={~p"/companies"} class="text-sm text-zinc-600 hover:text-zinc-900">Cancel</.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
