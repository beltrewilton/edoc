defmodule EdocWeb.UserLive.Settings do
  use EdocWeb, :live_view

  on_mount {EdocWeb.UserAuth, :require_sudo_mode}

  alias Edoc.Accounts
  @invalid_tenant_prefix "Not.Found.In.TenantContext"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <div class="mx-auto w-full max-w-3xl space-y-5">
        <.header>
          Account Settings
          <:subtitle>Manage tenant, email address, and password settings.</:subtitle>
        </.header>

        <.surface class="space-y-4 border-indigo-100/70 dark:border-indigo-500/20">
          <div>
            <h2 class="text-base font-semibold text-slate-900 dark:text-slate-100">Tenant</h2>
            <p class="text-sm text-slate-500 dark:text-slate-400">
              Set your tenant once. After creation, this field becomes locked.
            </p>
          </div>

          <.form
            for={@tenant_form}
            id="tenant_form"
            phx-submit="update_tenant"
            phx-change="validate_tenant"
            class="space-y-3"
          >
            <.input
              field={@tenant_form[:tenant]}
              type="text"
              label="Tenant"
              readonly={@tenant_locked}
              disabled={@tenant_locked}
              required
            />
            <.button type="submit" phx-disable-with="Saving..." disabled={@tenant_locked}>
              Update tenant
            </.button>
          </.form>
        </.surface>

        <.surface class="space-y-4 border-indigo-100/70 dark:border-indigo-500/20">
          <div>
            <h2 class="text-base font-semibold text-slate-900 dark:text-slate-100">Email</h2>
            <p class="text-sm text-slate-500 dark:text-slate-400">
              Use a valid address where you can receive confirmation links.
            </p>
          </div>

          <.form
            for={@email_form}
            id="email_form"
            phx-submit="update_email"
            phx-change="validate_email"
            class="space-y-3"
          >
            <.input
              field={@email_form[:email]}
              type="email"
              label="Email"
              autocomplete="username"
              required
            />
            <.button type="submit" phx-disable-with="Changing...">Change email</.button>
          </.form>
        </.surface>

        <.surface class="space-y-4 border-indigo-100/70 dark:border-indigo-500/20">
          <div>
            <h2 class="text-base font-semibold text-slate-900 dark:text-slate-100">Password</h2>
            <p class="text-sm text-slate-500 dark:text-slate-400">
              Set a new password for your next authenticated session.
            </p>
          </div>

          <.form
            for={@password_form}
            id="password_form"
            action={~p"/users/update-password"}
            method="post"
            phx-change="validate_password"
            phx-submit="update_password"
            phx-trigger-action={@trigger_submit}
            class="space-y-3"
          >
            <input
              name={@password_form[:email].name}
              type="hidden"
              id="hidden_user_email"
              autocomplete="username"
              value={@current_email}
            />
            <.input
              field={@password_form[:password]}
              type="password"
              label="New password"
              autocomplete="new-password"
              required
            />
            <.input
              field={@password_form[:password_confirmation]}
              type="password"
              label="Confirm new password"
              autocomplete="new-password"
            />
            <.button type="submit" phx-disable-with="Saving...">Save password</.button>
          </.form>
        </.surface>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, socket |> assign(:page_title, "Account Settings") |> push_navigate(to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)
    tenant_changeset = Accounts.change_user_tenant(user, %{})

    socket =
      socket
      |> assign(:page_title, "Account Settings")
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:tenant_form, to_form(tenant_changeset))
      |> assign(:tenant_locked, tenant_exists?(user.tenant))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_tenant", params, socket) do
    %{"user" => user_params} = params

    tenant_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_tenant(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, tenant_form: tenant_form)}
  end

  def handle_event("update_tenant", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    if socket.assigns.tenant_locked do
      {:noreply, socket}
    else
      case Accounts.update_user_tenant(user, user_params) do
        {:ok, user} ->
          tenant = Map.get(user_params, "tenant")

          case tenant_exists?(tenant) do
            true ->
              {:noreply,
               socket
               |> assign(:tenant_form, to_form(Accounts.change_user_tenant(user, %{})))
               |> assign(:tenant_locked, true)
               |> put_flash(:info, "Tenant already exists and is now locked.")
               |> schedule_companies_redirect()}

            false ->
              case Triplex.create(tenant) do
                {:ok, _} ->
                  {:noreply,
                   socket
                   |> assign(:tenant_form, to_form(Accounts.change_user_tenant(user, %{})))
                   |> assign(:tenant_locked, true)
                   |> put_flash(:info, "Tenant updated and created successfully.")
                   |> schedule_companies_redirect()}

                {:error, reason} ->
                  {:noreply,
                   socket
                   |> assign(:tenant_form, to_form(Accounts.change_user_tenant(user, %{})))
                   |> put_flash(:error, "Failed to create tenant: #{reason}")}
              end
          end

        {:error, changeset} ->
          {:noreply, assign(socket, tenant_form: to_form(changeset, action: :insert))}
      end
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  @impl true
  def handle_info(:redirect_to_companies_after_tenant_update, socket) do
    {:noreply, push_navigate(socket, to: ~p"/companies")}
  end

  defp tenant_exists?(tenant) when is_binary(tenant) do
    cond do
      tenant == "" ->
        false

      String.starts_with?(tenant, @invalid_tenant_prefix) ->
        false

      true ->
        try do
          Triplex.exists?(tenant)
        rescue
          _ -> false
        end
    end
  end

  defp tenant_exists?(_), do: false

  defp schedule_companies_redirect(socket) do
    Process.send_after(self(), :redirect_to_companies_after_tenant_update, 500)
    socket
  end
end
