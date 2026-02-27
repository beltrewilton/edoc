defmodule EdocWeb.UserLive.Confirmation do
  use EdocWeb, :live_view

  alias Edoc.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <div class="mx-auto w-full max-w-2xl space-y-5">
        <.header>
          Welcome {@user.email}
          <:subtitle>
            Complete confirmation to continue.
          </:subtitle>
        </.header>

        <.surface class="space-y-4 border-indigo-100/70 dark:border-indigo-500/20">
          <.form
            :if={!@user.confirmed_at}
            for={@form}
            id="confirmation_form"
            phx-mounted={JS.focus_first()}
            phx-submit="submit"
            action={~p"/users/log-in?_action=confirmed"}
            phx-trigger-action={@trigger_submit}
            class="space-y-3"
          >
            <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
            <.button
              type="submit"
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with="Confirming..."
              class="w-full"
            >
              Confirm and stay logged in
            </.button>
            <.button type="submit" variant="secondary" phx-disable-with="Confirming..." class="w-full">
              Confirm and log in only this time
            </.button>
          </.form>

          <.form
            :if={@user.confirmed_at}
            for={@form}
            id="login_form"
            phx-submit="submit"
            phx-mounted={JS.focus_first()}
            action={~p"/users/log-in"}
            phx-trigger-action={@trigger_submit}
            class="space-y-3"
          >
            <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
            <%= if @current_scope do %>
              <.button type="submit" phx-disable-with="Logging in..." class="w-full">
                Log in
              </.button>
            <% else %>
              <.button
                type="submit"
                name={@form[:remember_me].name}
                value="true"
                phx-disable-with="Logging in..."
                class="w-full"
              >
                Keep me logged in on this device
              </.button>
              <.button type="submit" variant="secondary" phx-disable-with="Logging in..." class="w-full">
                Log me in only this time
              </.button>
            <% end %>
          </.form>

          <p :if={!@user.confirmed_at} class="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800 dark:border-amber-500/45 dark:bg-amber-500/15 dark:text-amber-300">
            Tip: If you prefer passwords, you can enable them in user settings after sign-in.
          </p>
        </.surface>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok, assign(socket, user: user, form: form, trigger_submit: false, page_title: "Log in"),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "Magic link is invalid or it has expired.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
