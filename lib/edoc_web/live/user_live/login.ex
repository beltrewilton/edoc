defmodule EdocWeb.UserLive.Login do
  use EdocWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <div class="mx-auto w-full max-w-xl space-y-5">
        <.header>
          Log in
          <:subtitle>Sign in using your Google account.</:subtitle>
        </.header>

        <.surface class="border-indigo-100/70 dark:border-indigo-500/20">
          <a
            href={~p"/google_auth_url"}
            class={[
              ui(:btn_primary),
              "inline-flex w-full items-center justify-center gap-2 rounded-xl px-4 py-3 text-sm font-semibold transition shadow-[0_18px_36px_-24px_rgba(79,70,229,0.95)]"
            ]}
          >
            <.icon name="hero-arrow-right-on-rectangle" class="size-5" />
            Continue with Google
          </a>
        </.surface>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    socket =
      if params["access"] == "required" and is_nil(user_from_scope(socket.assigns.current_scope)) do
        put_flash(socket, :error, "Please sign in to access this section.")
      else
        socket
      end

    {:ok, assign(socket, page_title: "Log in")}
  end

  defp user_from_scope(%{user: user}) when not is_nil(user), do: user
  defp user_from_scope(_), do: nil
end
