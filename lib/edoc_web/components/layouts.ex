defmodule EdocWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality used by your application.
  """
  use EdocWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :page_title, :string, default: nil

  slot :inner_block, required: true

  def app(assigns) do
    section = section_from_title(assigns[:page_title])

    assigns =
      assigns
      |> assign(:signed_in?, signed_in?(assigns.current_scope))
      |> assign(:section, section)

    ~H"""
    <div class={[ui(:page_bg), "min-h-screen w-full"]}>
      <%= if @section == :landing do %>
        <header class="border-b border-slate-200/80 bg-white/80 backdrop-blur dark:border-slate-800 dark:bg-slate-950/70">
          <div class="mx-auto flex w-full max-w-7xl items-center justify-between px-4 py-4 sm:px-6">
            <.link navigate={~p"/"} class="inline-flex items-center gap-2">
              <img src={~p"/images/logo.svg"} width="28" alt="eDOC" />
              <span class="text-xs font-semibold uppercase tracking-[0.24em] text-slate-500 dark:text-slate-400">
                eDOC
              </span>
            </.link>

            <div class="flex items-center gap-2">
              <.theme_toggle />

              <%= if @signed_in? do %>
                <.button navigate={~p"/companies"} class="px-3.5 py-2">
                  Open dashboard
                </.button>
                <.button href={~p"/users/log-out"} method="delete" variant="ghost" class="px-3 py-2">
                  Log out
                </.button>
              <% else %>
                <.button navigate={~p"/users/log-in"} class="px-4 py-2.5 shadow-[0_14px_30px_-18px_rgba(79,70,229,0.95)]">
                  <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
                  Log in
                </.button>
              <% end %>
            </div>
          </div>
        </header>

        <main class="mx-auto w-full max-w-7xl px-4 py-10 sm:px-6 sm:py-14">
          {render_slot(@inner_block)}
        </main>
      <% else %>
        <div class="w-full">
          <div class="grid min-h-screen w-full grid-cols-1 lg:grid-cols-[16rem_minmax(0,1fr)]">
            <aside class="hidden border-r border-slate-200/80 bg-slate-50/70 lg:block dark:border-slate-800 dark:bg-slate-950/35">
              <div class="flex h-full flex-col p-5">
                <div class="flex items-center justify-between">
                  <.link navigate={~p"/"} class="inline-flex items-center gap-2">
                    <img src={~p"/images/logo.svg"} width="28" alt="eDOC" />
                    <span class="text-xs font-semibold uppercase tracking-[0.24em] text-slate-500 dark:text-slate-400">
                      eDOC
                    </span>
                  </.link>
                  <button type="button" class="rounded-lg p-1 text-slate-400 transition hover:bg-slate-200/70 hover:text-slate-600 dark:hover:bg-slate-800 dark:hover:text-slate-300">
                    <.icon name="hero-ellipsis-horizontal" class="size-5" />
                  </button>
                </div>

                <div class="mt-8">
                  <div>
                    <p class="px-2 text-xs font-semibold uppercase tracking-[0.18em] text-slate-400 dark:text-slate-500">
                      Navigation
                    </p>
                    <nav class="mt-3 space-y-1">
                      <.side_link
                        icon="hero-home"
                        label="Landing"
                        href={~p"/"}
                        active={@section == :landing}
                      />
                      <.side_link
                        icon="hero-building-office-2"
                        label="Companies"
                        href={authed_path(@signed_in?, ~p"/companies")}
                        active={@section in [:companies, :transactions]}
                      />
                      <.side_link
                        icon="hero-receipt-percent"
                        label="Transactions"
                        href={authed_path(@signed_in?, ~p"/companies")}
                        active={@section == :transactions}
                      />
                      <.side_link
                        icon="hero-numbered-list"
                        label="Tax Sequences"
                        href={authed_path(@signed_in?, ~p"/tax-sequences")}
                        active={@section == :tax_sequences}
                      />
                      <.side_link
                        icon="hero-cog-6-tooth"
                        label="Settings"
                        href={authed_path(@signed_in?, ~p"/users/settings")}
                        active={@section == :settings}
                      />
                    </nav>
                  </div>
                </div>
              </div>
            </aside>

            <div class="min-w-0">
              <header class="border-b border-slate-200/80 bg-white/85 px-4 py-3 backdrop-blur sm:px-6 dark:border-slate-800 dark:bg-slate-900/65">
                <div class="flex flex-wrap items-center gap-3">
                  <div class="relative min-w-[14rem] flex-1 max-w-2xl">
                    <.icon
                      name="hero-magnifying-glass"
                      class="pointer-events-none absolute left-3 top-1/2 size-5 -translate-y-1/2 text-slate-400 dark:text-slate-500"
                    />
                    <input
                      type="search"
                      placeholder="Search projects..."
                      class={[ui(:input), "pl-10 pr-10"]}
                    />
                    <span class="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 rounded-md border border-slate-200 bg-slate-50 px-1.5 py-0.5 text-[0.65rem] font-semibold uppercase tracking-wide text-slate-500 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-400">
                      /
                    </span>
                  </div>

                  <div class="ml-auto flex items-center gap-2">
                    <.theme_toggle />

                    <%= if @signed_in? do %>
                      <.button href={~p"/users/log-out"} method="delete" variant="ghost" class="px-3 py-2">
                        Log out
                      </.button>
                    <% else %>
                      <.button navigate={~p"/users/log-in"} variant="ghost" class="px-3 py-2">
                        Log in
                      </.button>
                    <% end %>
                  </div>
                </div>
              </header>

              <main class="space-y-6 px-4 py-6 sm:px-6">
                {render_slot(@inner_block)}
              </main>
            </div>
          </div>
        </div>
      <% end %>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" class="pointer-events-none fixed inset-x-0 top-5 z-50 px-4 sm:px-6">
      <div class="mx-auto flex w-full max-w-7xl justify-end">
        <div class="space-y-3">
          <.flash kind={:info} flash={@flash} />
          <.flash kind={:error} flash={@flash} />

          <.flash
            id="client-error"
            kind={:error}
            title={gettext("We can't find the internet")}
            phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
            phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
            hidden
          >
            {gettext("Attempting to reconnect")}
            <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
          </.flash>

          <.flash
            id="server-error"
            kind={:error}
            title={gettext("Something went wrong!")}
            phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
            phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
            hidden
          >
            {gettext("Attempting to reconnect")}
            <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
          </.flash>
        </div>
      </div>
    </div>
    """
  end

  def theme_toggle(assigns) do
    ~H"""
    <div class="inline-flex items-center gap-1 rounded-xl border border-slate-200 bg-white p-1 dark:border-slate-700 dark:bg-slate-900/80">
      <button
        type="button"
        class="rounded-lg p-1.5 text-slate-500 transition hover:bg-slate-100 hover:text-slate-800 dark:text-slate-400 dark:hover:bg-slate-800 dark:hover:text-slate-100"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="System theme"
      >
        <.icon name="hero-computer-desktop" class="size-4" />
      </button>
      <button
        type="button"
        class="rounded-lg p-1.5 text-slate-500 transition hover:bg-slate-100 hover:text-slate-800 dark:text-slate-400 dark:hover:bg-slate-800 dark:hover:text-slate-100"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Light theme"
      >
        <.icon name="hero-sun" class="size-4" />
      </button>
      <button
        type="button"
        class="rounded-lg p-1.5 text-slate-500 transition hover:bg-slate-100 hover:text-slate-800 dark:text-slate-400 dark:hover:bg-slate-800 dark:hover:text-slate-100"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Dark theme"
      >
        <.icon name="hero-moon" class="size-4" />
      </button>
    </div>
    """
  end

  attr :href, :string, required: true
  attr :active, :boolean, default: false
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp side_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "flex items-center gap-3 rounded-xl px-2.5 py-2 text-sm font-medium transition",
        @active &&
          "bg-indigo-50 text-indigo-700 dark:bg-indigo-500/15 dark:text-indigo-300",
        !@active &&
          "text-slate-600 hover:bg-slate-200/70 hover:text-slate-900 dark:text-slate-300 dark:hover:bg-slate-800 dark:hover:text-slate-100"
      ]}
    >
      <.icon name={@icon} class="size-5" />
      <span>{@label}</span>
    </.link>
    """
  end

  defp signed_in?(%{user: user}) when not is_nil(user), do: true
  defp signed_in?(_), do: false

  defp authed_path(true, path), do: path
  defp authed_path(false, _path), do: ~p"/users/log-in?access=required"

  defp section_from_title(nil), do: :landing

  defp section_from_title(title) when is_binary(title) do
    down = String.downcase(title)

    cond do
      String.contains?(down, "transaction") -> :transactions
      String.contains?(down, "company") or String.contains?(down, "companies") -> :companies
      String.contains?(down, "tax") -> :tax_sequences
      String.contains?(down, "setting") -> :settings
      true -> :landing
    end
  end
end
