defmodule EdocWeb.UserLive.Settings do
  use EdocWeb, :live_view

  on_mount {EdocWeb.UserAuth, :require_sudo_mode}

  alias Edoc.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>
          Account Settings
          <:subtitle>Manage your account email address and password settings</:subtitle>
        </.header>
      </div>

      <.form
        for={@tenant_form}
        id="tenant_form"
        phx-submit="update_tenant"
        phx-change="validate_tenant"
      >
        <.input
          field={@tenant_form[:tenant]}
          type="text"
          label="Tenant"
          readonly={@tenant_locked}
          disabled={@tenant_locked}
          required
        />
        <.button variant="primary" phx-disable-with="Saving..." disabled={@tenant_locked}>
          Update Tenant
        </.button>
      </.form>

      <div class="divider" />

      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          required
        />
        <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
      </.form>

      <div class="divider" />

      <.form
        for={@password_form}
        id="password_form"
        action={~p"/users/update-password"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
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
        <.button variant="primary" phx-disable-with="Saving...">
          Save Password
        </.button>
      </.form>
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

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)
    tenant_changeset = Accounts.change_user_tenant(user, %{})

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:tenant_form, to_form(tenant_changeset))
      |> assign(:tenant_locked, Triplex.exists?(user.tenant))
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

          case Triplex.exists?(tenant) do
            true ->
              {:noreply,
               socket
               |> assign(:tenant_form, to_form(Accounts.change_user_tenant(user, %{})))
               |> assign(:tenant_locked, true)
               |> put_flash(:info, "Tenant already exists and is now locked.")}

            false ->
              case Triplex.create(tenant) do
                {:ok, _} ->
                  {:noreply,
                   socket
                   |> assign(:tenant_form, to_form(Accounts.change_user_tenant(user, %{})))
                   |> assign(:tenant_locked, true)
                   |> put_flash(:info, "Tenant updated and created successfully.")}

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
end
