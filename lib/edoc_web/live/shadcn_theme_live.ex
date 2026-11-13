defmodule EdocWeb.ShadcnThemeLive do
  use EdocWeb, :live_view

  @themes [
    %{
      id: "clean-slate",
      name: "Clean Slate",
      summary: "Balanced default for dashboards, forms, and dense LiveView screens."
    },
    %{
      id: "catppuccin",
      name: "Catppuccin",
      summary: "Soft pastel contrast with cooler accents from the shadcn registry palette."
    },
    %{
      id: "graphite",
      name: "Graphite",
      summary: "Neutral monochrome shell with strong contrast for operational interfaces."
    },
    %{
      id: "kodama-grove",
      name: "Kodama Grove",
      summary: "Warm editorial greens and earthy neutrals with softer organic contrast."
    },
    %{
      id: "doom-64",
      name: "Doom 64",
      summary: "Industrial arcade palette with square corners, sharp contrast, and retro sci-fi type."
    }
  ]

  @theme_ids Enum.map(@themes, & &1.id)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Shadcn Themes")
     |> assign(:themes, @themes)
     |> assign(:selected_theme, "clean-slate")
     |> assign(:form, demo_form())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    selected_theme =
      params
      |> Map.get("theme", "clean-slate")
      |> normalize_theme()

    {:noreply, assign(socket, :selected_theme, selected_theme)}
  end

  @impl true
  def handle_event("select_theme", %{"theme_picker" => %{"theme" => theme}}, socket) do
    {:noreply, push_patch(socket, to: ~p"/themes/shadcn?#{[theme: normalize_theme(theme)]}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:topbar_actions>
        <.form
          for={to_form(%{"theme" => @selected_theme}, as: :theme_picker)}
          id="theme-picker-form"
          phx-change="select_theme"
        >
          <div data-shadcn-theme={@selected_theme} class="min-w-[13rem]">
            <.input
              field={to_form(%{"theme" => @selected_theme}, as: :theme_picker)[:theme]}
              type="select"
              label={nil}
              options={Enum.map(@themes, &{&1.name, &1.id})}
              class="block w-full rounded-xl border border-slate-200 bg-white px-3.5 py-2 text-sm text-slate-900 shadow-sm outline-none transition focus:border-indigo-400 focus:ring-2 focus:ring-indigo-200 dark:border-slate-700 dark:bg-slate-900/80 dark:text-slate-100 dark:focus:border-indigo-500 dark:focus:ring-indigo-500/25"
            />
          </div>
        </.form>
      </:topbar_actions>

      <div data-shadcn-theme={@selected_theme} class="space-y-6">
        <section class="overflow-hidden rounded-[calc(var(--sd-radius)*2.2)] border border-[var(--sd-border)] bg-[var(--sd-panel)] text-[var(--sd-foreground)] shadow-[var(--sd-shadow-xl)]">
          <div class="border-b border-[var(--sd-border)] bg-[var(--sd-card)] px-6 py-6 sm:px-8">
            <div class="max-w-3xl space-y-4">
              <div class="flex flex-wrap items-center gap-3">
                <span class="inline-flex items-center rounded-full border border-[var(--sd-border)] bg-[var(--sd-muted)] px-3 py-1 text-[0.7rem] font-semibold uppercase tracking-[0.22em] text-[var(--sd-muted-foreground)]">
                  shadcn registry
                </span>
                <span class="inline-flex items-center rounded-full bg-[var(--sd-primary)] px-3 py-1 text-xs font-semibold text-[var(--sd-primary-foreground)] shadow-[var(--sd-shadow-sm)]">
                  Theme playground
                </span>
                <span class="rounded-full border border-[var(--sd-border)] px-2.5 py-1 text-[0.7rem] font-semibold uppercase tracking-[0.16em] text-[var(--sd-muted-foreground)]">
                  {String.upcase(@selected_theme)}
                </span>
              </div>

              <nav aria-label="Breadcrumb" class="flex flex-wrap items-center gap-2 text-sm text-[var(--sd-muted-foreground)]">
                <.link navigate={~p"/"} class="transition hover:text-[var(--sd-foreground)]">Home</.link>
                <.icon name="hero-chevron-right" class="size-4" />
                <span>Theme Lab</span>
                <.icon name="hero-chevron-right" class="size-4" />
                <span class="font-medium text-[var(--sd-foreground)]">{theme_name(@selected_theme)}</span>
              </nav>

              <div>
                <h1 class="text-4xl font-semibold tracking-[-0.04em] sm:text-5xl">
                  Phoenix + LiveView component page with shadcn-style tokens
                </h1>
                <p class="mt-3 max-w-2xl text-sm leading-7 text-[var(--sd-muted-foreground)] sm:text-base">
                  This page stays server-rendered, uses the existing Tailwind pipeline, and exposes the
                  `clean-slate`, `catppuccin`, `graphite`, `kodama-grove`, and `doom-64` registry themes as URL-pickable visual tokens.
                </p>
              </div>
            </div>
          </div>

          <div class="grid gap-6 p-6 sm:p-8 2xl:grid-cols-[1.2fr_0.8fr]">
            <section class="space-y-6">
              <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
                <.stat_card icon="hero-bolt" title="Response Time" value="83ms" detail="Median round-trip on invoice save." />
                <.stat_card icon="hero-building-office-2" title="Active Companies" value="128" detail="Multi-tenant entities connected to DGII." />
                <.stat_card icon="hero-receipt-percent" title="Invoices Queued" value="4,392" detail="Ready for provider dispatch in the next cycle." />
                <.stat_card icon="hero-shield-check" title="Validation Pass" value="99.2%" detail="Recent payload integrity across pipelines." />
              </div>

              <div class="grid gap-6 xl:grid-cols-[1.15fr_0.85fr]">
                <article class="rounded-[calc(var(--sd-radius)*1.8)] border border-[var(--sd-border)] bg-[var(--sd-card)] shadow-[var(--sd-shadow-md)]">
                  <div class="flex items-center justify-between gap-4 border-b border-[var(--sd-border)] px-5 py-4">
                    <div>
                      <h2 class="text-lg font-semibold">Invoice Intake</h2>
                      <p class="text-sm text-[var(--sd-muted-foreground)]">Inputs, toggles, radios, checkboxes, and actions.</p>
                    </div>
                    <div class="flex items-center gap-2">
                      <button class="inline-flex items-center rounded-full border border-[var(--sd-border)] bg-[var(--sd-muted)] px-2.5 py-1 text-xs font-medium text-[var(--sd-muted-foreground)] transition hover:bg-[var(--sd-accent)] hover:text-[var(--sd-accent-foreground)]">
                        Draft
                      </button>
                      <button class="inline-flex items-center rounded-full bg-[var(--sd-primary)] px-2.5 py-1 text-xs font-semibold text-[var(--sd-primary-foreground)] shadow-[var(--sd-shadow-sm)]">
                        Synced
                      </button>
                    </div>
                  </div>

                  <.form for={@form} id="shadcn-demo-form" class="grid gap-5 p-5">
                    <div class="grid gap-5 md:grid-cols-2">
                      <.input field={@form[:company]} label="Company" placeholder="Northwind Dominicana" />
                      <.input field={@form[:email]} type="email" label="Notification Email" placeholder="ops@northwind.do" />
                      <.input field={@form[:document]} label="Document No." placeholder="E310000000412" />
                      <.input field={@form[:queue]} type="select" label="Queue" options={["Default", "Priority", "Review"]} />
                    </div>

                    <.input field={@form[:notes]} type="textarea" label="Notes" rows="4" placeholder="Add reviewer notes, provider guidance, or reconciliation flags." />

                    <div class="grid gap-4 md:grid-cols-2">
                      <div class="rounded-[calc(var(--sd-radius)*1.5)] border border-[var(--sd-border)] bg-[var(--sd-panel)] p-4">
                        <p class="text-sm font-semibold">Processing Mode</p>
                        <div class="mt-3 space-y-3 text-sm">
                          <label class="flex items-center gap-3">
                            <input type="radio" name="mode" checked class="size-4 border-[var(--sd-border)] text-[var(--sd-primary)] focus:ring-[var(--sd-ring)]" />
                            <span>Automatic dispatch</span>
                          </label>
                          <label class="flex items-center gap-3">
                            <input type="radio" name="mode" class="size-4 border-[var(--sd-border)] text-[var(--sd-primary)] focus:ring-[var(--sd-ring)]" />
                            <span>Manual approval</span>
                          </label>
                        </div>
                      </div>

                      <div class="rounded-[calc(var(--sd-radius)*1.5)] border border-[var(--sd-border)] bg-[var(--sd-panel)] p-4">
                        <p class="text-sm font-semibold">Rules</p>
                        <div class="mt-3 space-y-3">
                          <.input field={@form[:notify]} type="checkbox" label="Notify accounting team on retry" />
                          <.input field={@form[:archive]} type="checkbox" label="Archive source XML after provider acceptance" />
                        </div>
                      </div>
                    </div>

                    <div class="flex flex-wrap items-center gap-3">
                      <button type="button" class="inline-flex items-center gap-2 rounded-[var(--sd-radius)] bg-[var(--sd-primary)] px-4 py-2.5 text-sm font-semibold text-[var(--sd-primary-foreground)] shadow-[var(--sd-shadow-sm)] transition hover:brightness-110">
                        <.icon name="hero-paper-airplane" class="size-4" />
                        Submit
                      </button>
                      <button type="button" class="inline-flex items-center gap-2 rounded-[var(--sd-radius)] border border-[var(--sd-border)] bg-[var(--sd-card)] px-4 py-2.5 text-sm font-semibold transition hover:bg-[var(--sd-muted)]">
                        <.icon name="hero-pencil-square" class="size-4" />
                        Save draft
                      </button>
                      <button type="button" class="inline-flex items-center gap-2 rounded-[var(--sd-radius)] px-4 py-2.5 text-sm font-medium text-[var(--sd-muted-foreground)] transition hover:bg-[var(--sd-muted)] hover:text-[var(--sd-foreground)]">
                        Reset
                      </button>
                    </div>
                  </.form>
                </article>

                <div class="space-y-6">
                  <article class="rounded-[calc(var(--sd-radius)*1.8)] border border-[var(--sd-border)] bg-[var(--sd-card)] p-5 shadow-[var(--sd-shadow-md)]">
                    <div class="flex items-start justify-between gap-4">
                      <div>
                        <h2 class="text-lg font-semibold">Team Presence</h2>
                        <p class="text-sm text-[var(--sd-muted-foreground)]">Avatar cluster, badges, and compact actions.</p>
                      </div>
                      <button class="rounded-[var(--sd-radius)] border border-[var(--sd-border)] p-2 text-[var(--sd-muted-foreground)] transition hover:bg-[var(--sd-muted)] hover:text-[var(--sd-foreground)]">
                        <.icon name="hero-ellipsis-horizontal" class="size-5" />
                      </button>
                    </div>

                    <div class="mt-5 flex items-center gap-4">
                      <div class="flex -space-x-3">
                        <.theme_avatar initials="JD" accent="bg-[var(--sd-primary)] text-[var(--sd-primary-foreground)]" />
                        <.theme_avatar initials="AR" accent="bg-emerald-500 text-white" />
                        <.theme_avatar initials="MP" accent="bg-amber-400 text-slate-950" />
                        <div class="inline-flex size-11 items-center justify-center rounded-full border-2 border-[var(--sd-card)] bg-[var(--sd-muted)] text-xs font-semibold text-[var(--sd-muted-foreground)]">+6</div>
                      </div>
                      <div class="flex flex-wrap gap-2">
                        <span class="rounded-full bg-[var(--sd-accent)] px-3 py-1 text-xs font-semibold text-[var(--sd-accent-foreground)]">Reviewer</span>
                        <span class="rounded-full border border-[var(--sd-border)] px-3 py-1 text-xs font-medium text-[var(--sd-muted-foreground)]">Provider API</span>
                        <span class="rounded-full border border-emerald-300 bg-emerald-500/10 px-3 py-1 text-xs font-semibold text-emerald-700 dark:border-emerald-500/40 dark:text-emerald-300">Healthy</span>
                      </div>
                    </div>
                  </article>

                  <article class="rounded-[calc(var(--sd-radius)*1.8)] border border-[var(--sd-border)] bg-[var(--sd-card)] p-5 shadow-[var(--sd-shadow-md)]">
                    <div class="flex items-center justify-between gap-4">
                      <div>
                        <h2 class="text-lg font-semibold">Tabs</h2>
                        <p class="text-sm text-[var(--sd-muted-foreground)]">Static shadcn-inspired tab bar.</p>
                      </div>
                    </div>
                    <div class="mt-4 inline-flex rounded-[calc(var(--sd-radius)*1.4)] border border-[var(--sd-border)] bg-[var(--sd-muted)] p-1">
                      <button class="rounded-[var(--sd-radius)] bg-[var(--sd-card)] px-4 py-2 text-sm font-semibold shadow-[var(--sd-shadow-xs)]">Overview</button>
                      <button class="rounded-[var(--sd-radius)] px-4 py-2 text-sm text-[var(--sd-muted-foreground)] transition hover:text-[var(--sd-foreground)]">Activity</button>
                      <button class="rounded-[var(--sd-radius)] px-4 py-2 text-sm text-[var(--sd-muted-foreground)] transition hover:text-[var(--sd-foreground)]">Webhooks</button>
                    </div>
                  </article>

                  <article class="rounded-[calc(var(--sd-radius)*1.8)] border border-[var(--sd-border)] bg-[var(--sd-card)] p-5 shadow-[var(--sd-shadow-md)]">
                    <div class="flex items-center justify-between gap-4">
                      <div>
                        <h2 class="text-lg font-semibold">Status</h2>
                        <p class="text-sm text-[var(--sd-muted-foreground)]">Alert, progress, and switch controls.</p>
                      </div>
                    </div>

                    <div class="mt-4 rounded-[calc(var(--sd-radius)*1.4)] border border-[var(--sd-border)] bg-[var(--sd-muted)] p-4">
                      <div class="flex items-start gap-3">
                        <div class="mt-0.5 rounded-full bg-[color-mix(in_oklab,var(--sd-primary)_16%,white)] p-2 text-[var(--sd-primary)] dark:bg-[color-mix(in_oklab,var(--sd-primary)_18%,transparent)]">
                          <.icon name="hero-information-circle" class="size-5" />
                        </div>
                        <div>
                          <p class="text-sm font-semibold">Provider handshake in progress</p>
                          <p class="mt-1 text-sm text-[var(--sd-muted-foreground)]">
                            Recent retries are under the alert threshold, but one tenant is waiting on callback confirmation.
                          </p>
                        </div>
                      </div>
                    </div>

                    <div class="mt-4 space-y-4">
                      <div>
                        <div class="mb-2 flex items-center justify-between text-sm">
                          <span>Registry sync</span>
                          <span class="text-[var(--sd-muted-foreground)]">72%</span>
                        </div>
                        <div class="h-2.5 rounded-full bg-[var(--sd-muted)]">
                          <div class="h-2.5 w-[72%] rounded-full bg-[var(--sd-primary)]"></div>
                        </div>
                      </div>

                      <label class="flex items-center justify-between rounded-[calc(var(--sd-radius)*1.4)] border border-[var(--sd-border)] bg-[var(--sd-panel)] px-4 py-3">
                        <div>
                          <p class="text-sm font-semibold">Auto-approve safe invoices</p>
                          <p class="text-xs text-[var(--sd-muted-foreground)]">Enable policy-based release after validator pass.</p>
                        </div>
                        <span class="relative inline-flex h-6 w-11 items-center rounded-full bg-[var(--sd-primary)]">
                          <span class="absolute right-1 inline-flex size-4 rounded-full bg-white shadow"></span>
                        </span>
                      </label>
                    </div>
                  </article>
                </div>
              </div>

              <article class="rounded-[calc(var(--sd-radius)*1.8)] border border-[var(--sd-border)] bg-[var(--sd-card)] shadow-[var(--sd-shadow-md)]">
                <div class="flex flex-col gap-3 border-b border-[var(--sd-border)] px-5 py-4 sm:flex-row sm:items-center sm:justify-between">
                  <div>
                    <h2 class="text-lg font-semibold">Recent Transactions</h2>
                    <p class="text-sm text-[var(--sd-muted-foreground)]">Command input, table, dropdown trigger, and pagination.</p>
                  </div>
                  <div class="relative w-full max-w-sm">
                    <.icon name="hero-magnifying-glass" class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--sd-muted-foreground)]" />
                    <input type="search" value="RNC or document number" class="w-full rounded-[var(--sd-radius)] border border-[var(--sd-border)] bg-[var(--sd-panel)] py-2 pl-9 pr-3 text-sm text-[var(--sd-muted-foreground)] outline-none" />
                  </div>
                </div>

                <div class="overflow-x-auto">
                  <table class="min-w-full text-left text-sm">
                    <thead class="bg-[var(--sd-muted)] text-[var(--sd-muted-foreground)]">
                      <tr>
                        <th class="px-5 py-3 font-medium">Document</th>
                        <th class="px-5 py-3 font-medium">Company</th>
                        <th class="px-5 py-3 font-medium">Status</th>
                        <th class="px-5 py-3 font-medium">Latency</th>
                        <th class="px-5 py-3 font-medium text-right">Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for row <- transaction_rows() do %>
                        <tr class="border-t border-[var(--sd-border)]">
                          <td class="px-5 py-4">
                            <div class="font-medium">{row.document}</div>
                            <div class="text-xs text-[var(--sd-muted-foreground)]">{row.type}</div>
                          </td>
                          <td class="px-5 py-4">{row.company}</td>
                          <td class="px-5 py-4">
                            <span class={[
                              "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold",
                              status_class(row.status)
                            ]}>
                              {row.status}
                            </span>
                          </td>
                          <td class="px-5 py-4 text-[var(--sd-muted-foreground)]">{row.latency}</td>
                          <td class="px-5 py-4 text-right">
                            <button class="rounded-[var(--sd-radius)] border border-[var(--sd-border)] px-3 py-1.5 text-xs font-medium transition hover:bg-[var(--sd-muted)]">
                              Open
                            </button>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>

                <div class="flex flex-wrap items-center justify-between gap-3 border-t border-[var(--sd-border)] px-5 py-4">
                  <p class="text-sm text-[var(--sd-muted-foreground)]">Showing 4 of 128 transactions</p>
                  <div class="inline-flex rounded-[calc(var(--sd-radius)*1.4)] border border-[var(--sd-border)] bg-[var(--sd-panel)] p-1">
                    <button class="rounded-[var(--sd-radius)] px-3 py-1.5 text-sm text-[var(--sd-muted-foreground)] transition hover:text-[var(--sd-foreground)]">Previous</button>
                    <button class="rounded-[var(--sd-radius)] bg-[var(--sd-card)] px-3 py-1.5 text-sm font-semibold shadow-[var(--sd-shadow-xs)]">1</button>
                    <button class="rounded-[var(--sd-radius)] px-3 py-1.5 text-sm text-[var(--sd-muted-foreground)] transition hover:text-[var(--sd-foreground)]">2</button>
                    <button class="rounded-[var(--sd-radius)] px-3 py-1.5 text-sm text-[var(--sd-muted-foreground)] transition hover:text-[var(--sd-foreground)]">Next</button>
                  </div>
                </div>
              </article>

              <section class="space-y-6 pt-2">
                <div class="grid gap-6 xl:grid-cols-[1.1fr_0.6fr_1fr]">
                  <article class="rounded-[calc(var(--sd-radius)*1.8)] border border-[var(--sd-border)] bg-[var(--sd-card)] p-6 shadow-[var(--sd-shadow-md)]">
                    <p class="text-sm text-[var(--sd-muted-foreground)]">Total Revenue</p>
                    <p class="mt-4 text-5xl font-semibold tracking-[-0.05em]">$15,231.89</p>
                    <p class="mt-4 text-sm text-[var(--sd-muted-foreground)]">+20.1% from last month</p>

                    <div class="mt-8">
                      <svg viewBox="0 0 420 140" class="h-40 w-full" aria-label="Revenue trend">
                        <path
                          d="M16 102 C50 88, 82 78, 112 82 S168 102, 202 104 S250 108, 288 102 S340 98, 366 96 S392 76, 404 34"
                          fill="none"
                          stroke="var(--sd-primary)"
                          stroke-width="3"
                          stroke-linecap="round"
                        />
                        <%= for {cx, cy} <- [{16, 102}, {70, 82}, {126, 106}, {182, 108}, {242, 112}, {314, 104}, {364, 100}, {404, 34}] do %>
                          <circle cx={cx} cy={cy} r="4.5" fill="var(--sd-card)" stroke="var(--sd-primary)" stroke-width="3" />
                        <% end %>
                      </svg>
                    </div>
                  </article>

                  <article class="rounded-[calc(var(--sd-radius)*1.8)] border border-[var(--sd-border)] bg-[var(--sd-card)] p-6 shadow-[var(--sd-shadow-md)]">
                    <div class="flex items-center justify-between">
                      <button class="rounded-[var(--sd-radius)] p-2 text-[var(--sd-muted-foreground)] transition hover:bg-[var(--sd-muted)] hover:text-[var(--sd-foreground)]">
                        <.icon name="hero-chevron-left" class="size-5" />
                      </button>
                      <h3 class="text-xl font-semibold">June 2025</h3>
                      <button class="rounded-[var(--sd-radius)] p-2 text-[var(--sd-muted-foreground)] transition hover:bg-[var(--sd-muted)] hover:text-[var(--sd-foreground)]">
                        <.icon name="hero-chevron-right" class="size-5" />
                      </button>
                    </div>

                    <div class="mt-5 grid grid-cols-7 gap-2 text-center text-sm text-[var(--sd-muted-foreground)]">
                      <%= for day <- ~w(Su Mo Tu We Th Fr Sa) do %>
                        <div>{day}</div>
                      <% end %>
                    </div>

                    <div class="mt-4 grid grid-cols-7 gap-2 text-center text-base">
                      <%= for day <- calendar_days() do %>
                        <div class={[
                          "flex aspect-square items-center justify-center rounded-[var(--sd-radius)]",
                          day.state == :range && "bg-sky-500 text-white",
                          day.state == :accent && "bg-[var(--sd-primary)] text-[var(--sd-primary-foreground)]",
                          day.state == :plain && "hover:bg-[var(--sd-muted)]",
                          day.state == :muted && "text-[var(--sd-muted-foreground)]"
                        ]}>
                          {day.label}
                        </div>
                      <% end %>
                    </div>
                  </article>

                  <article class="rounded-[calc(var(--sd-radius)*1.8)] border border-[var(--sd-border)] bg-[var(--sd-card)] p-6 shadow-[var(--sd-shadow-md)]">
                    <h3 class="text-2xl font-semibold tracking-[-0.03em]">Move Goal</h3>
                    <p class="mt-2 text-sm text-[var(--sd-muted-foreground)]">Set your daily activity goal.</p>

                    <div class="mt-8 flex items-center justify-center gap-6">
                      <button class="inline-flex size-12 items-center justify-center rounded-full border border-[var(--sd-border)] bg-[var(--sd-panel)] text-[var(--sd-muted-foreground)] shadow-[var(--sd-shadow-xs)]">
                        <.icon name="hero-minus" class="size-5" />
                      </button>
                      <div class="text-center">
                        <p class="text-6xl font-semibold tracking-[-0.06em]">350</p>
                        <p class="text-sm uppercase tracking-[0.18em] text-[var(--sd-muted-foreground)]">Calories/Day</p>
                      </div>
                      <button class="inline-flex size-12 items-center justify-center rounded-full border border-[var(--sd-border)] bg-[var(--sd-panel)] text-[var(--sd-muted-foreground)] shadow-[var(--sd-shadow-xs)]">
                        <.icon name="hero-plus" class="size-5" />
                      </button>
                    </div>

                    <div class="mt-8 flex h-32 items-end gap-3">
                      <%= for height <- [94, 70, 40, 70, 40, 64, 36, 54, 70, 40, 64, 36, 82] do %>
                        <div class="flex-1 rounded-t-[calc(var(--sd-radius)*1.1)] bg-[var(--sd-primary)]" style={"height: #{height}px"}></div>
                      <% end %>
                    </div>

                    <button class="mt-8 inline-flex w-full items-center justify-center rounded-[var(--sd-radius)] bg-[var(--sd-muted)] px-4 py-3 text-base font-medium text-[var(--sd-foreground)] transition hover:bg-[var(--sd-accent)] hover:text-[var(--sd-accent-foreground)]">
                      Set Goal
                    </button>
                  </article>
                </div>

                <div class="grid gap-6 xl:grid-cols-[0.95fr_1.45fr]">
                  <article class="rounded-[calc(var(--sd-radius)*1.8)] border border-[var(--sd-border)] bg-[var(--sd-card)] p-6 shadow-[var(--sd-shadow-md)]">
                    <h3 class="text-3xl font-semibold tracking-[-0.04em]">Upgrade your subscription</h3>
                    <p class="mt-4 text-sm leading-7 text-[var(--sd-muted-foreground)]">
                      You are currently on the free plan. Upgrade to the pro plan to get access to all features.
                    </p>

                    <div class="mt-8 grid gap-5 md:grid-cols-2">
                      <.input name="upgrade[name]" value="Evil Rabbit" label="Name" />
                      <.input name="upgrade[email]" type="email" value="example@acme.com" label="Email" />
                    </div>

                    <div class="mt-5 grid gap-5 md:grid-cols-[1.5fr_0.5fr_0.35fr]">
                      <.input name="upgrade[card]" value="1234 1234 1234 1234" label="Card Number" />
                      <.input name="upgrade[expiry]" value="MM/YY" label="Expiry" />
                      <.input name="upgrade[cvc]" value="CVC" label="CVC" />
                    </div>

                    <div class="mt-8">
                      <h4 class="text-lg font-semibold">Plan</h4>
                      <p class="mt-1 text-sm text-[var(--sd-muted-foreground)]">Select the plan that best fits your needs.</p>

                      <div class="mt-4 grid gap-4 md:grid-cols-2">
                        <label class="rounded-[calc(var(--sd-radius)*1.6)] border border-[var(--sd-border)] bg-[var(--sd-panel)] p-5 transition hover:border-[var(--sd-primary)]">
                          <div class="flex items-start gap-4">
                            <input type="radio" name="upgrade_plan" checked class="mt-1 size-5 border-[var(--sd-border)] text-[var(--sd-primary)] focus:ring-[var(--sd-ring)]" />
                            <div>
                              <p class="text-xl font-semibold">Starter Plan</p>
                              <p class="mt-1 text-sm text-[var(--sd-muted-foreground)]">Perfect for smaller teams and lightweight flows.</p>
                            </div>
                          </div>
                        </label>

                        <label class="rounded-[calc(var(--sd-radius)*1.6)] border border-[var(--sd-border)] bg-[var(--sd-card)] p-5 transition hover:border-[var(--sd-primary)]">
                          <div class="flex items-start gap-4">
                            <input type="radio" name="upgrade_plan" class="mt-1 size-5 border-[var(--sd-border)] text-[var(--sd-primary)] focus:ring-[var(--sd-ring)]" />
                            <div>
                              <p class="text-xl font-semibold">Pro Plan</p>
                              <p class="mt-1 text-sm text-[var(--sd-muted-foreground)]">More features, analytics, and workflow controls.</p>
                            </div>
                          </div>
                        </label>
                      </div>
                    </div>
                  </article>

                  <article class="rounded-[calc(var(--sd-radius)*1.8)] border border-[var(--sd-border)] bg-[var(--sd-card)] p-6 shadow-[var(--sd-shadow-md)]">
                    <h3 class="text-3xl font-semibold tracking-[-0.04em]">Exercise Minutes</h3>
                    <p class="mt-3 text-sm text-[var(--sd-muted-foreground)]">
                      Your exercise minutes are ahead of where you normally are.
                    </p>

                    <div class="mt-8">
                      <svg viewBox="0 0 720 320" class="h-[22rem] w-full" aria-label="Exercise line chart">
                        <%= for y <- [40, 100, 160, 220, 280] do %>
                          <line x1="40" y1={y} x2="680" y2={y} stroke="var(--sd-border)" stroke-width="1.5" />
                        <% end %>

                        <path
                          d="M40 212 C102 236, 132 244, 182 240 S270 42, 320 46 S392 174, 450 170 S536 148, 592 172 S646 178, 680 166"
                          fill="none"
                          stroke="var(--sd-primary)"
                          stroke-width="3.5"
                          stroke-linecap="round"
                        />
                        <path
                          d="M40 176 C96 186, 128 198, 182 206 S270 222, 320 218 S392 198, 450 206 S536 212, 592 206 S646 192, 680 182"
                          fill="none"
                          stroke="color-mix(in oklab, var(--sd-primary) 45%, white)"
                          stroke-width="3"
                          stroke-linecap="round"
                        />

                        <%= for {cx, cy} <- [{40, 212}, {148, 242}, {282, 46}, {392, 174}, {502, 150}, {600, 176}, {680, 166}] do %>
                          <circle cx={cx} cy={cy} r="4.5" fill="var(--sd-primary)" />
                        <% end %>
                        <%= for {cx, cy} <- [{40, 176}, {148, 198}, {282, 218}, {392, 206}, {502, 214}, {600, 206}, {680, 182}] do %>
                          <circle cx={cx} cy={cy} r="4" fill="color-mix(in oklab, var(--sd-primary) 45%, white)" />
                        <% end %>

                        <%= for {x, label} <- [{40, "Mon"}, {146, "Tue"}, {252, "Wed"}, {358, "Thu"}, {464, "Fri"}, {570, "Sat"}, {676, "Sun"}] do %>
                          <text x={x} y="314" text-anchor="middle" fill="var(--sd-muted-foreground)" font-size="15">{label}</text>
                        <% end %>
                      </svg>
                    </div>
                  </article>
                </div>
              </section>
            </section>

            <section class="space-y-6">
              <article class="rounded-[calc(var(--sd-radius)*1.8)] border border-[var(--sd-border)] bg-[var(--sd-card)] p-5 shadow-[var(--sd-shadow-md)]">
                <div class="flex items-center justify-between gap-3">
                  <div>
                    <h2 class="text-lg font-semibold">Review Queue</h2>
                    <p class="text-sm text-[var(--sd-muted-foreground)]">Skeletons, list rows, and contextual tags.</p>
                  </div>
                  <button class="rounded-[var(--sd-radius)] border border-[var(--sd-border)] px-3 py-1.5 text-xs font-medium transition hover:bg-[var(--sd-muted)]">
                    Refresh
                  </button>
                </div>

                <div class="mt-4 space-y-3">
                  <%= for item <- review_queue() do %>
                    <div class="flex items-center gap-3 rounded-[calc(var(--sd-radius)*1.4)] border border-[var(--sd-border)] bg-[var(--sd-panel)] p-3">
                      <div class="space-y-2">
                        <div class="h-3 w-20 rounded-full bg-[var(--sd-muted)]"></div>
                        <div class="h-3 w-14 rounded-full bg-[var(--sd-muted)]"></div>
                      </div>
                      <div class="min-w-0 flex-1">
                        <p class="truncate text-sm font-semibold">{item.title}</p>
                        <p class="truncate text-xs text-[var(--sd-muted-foreground)]">{item.meta}</p>
                      </div>
                      <span class="rounded-full bg-[var(--sd-accent)] px-2.5 py-1 text-xs font-semibold text-[var(--sd-accent-foreground)]">
                        {item.label}
                      </span>
                    </div>
                  <% end %>
                </div>
              </article>

              <article class="rounded-[calc(var(--sd-radius)*1.8)] border border-[var(--sd-border)] bg-[var(--sd-card)] p-5 shadow-[var(--sd-shadow-md)]">
                <div class="flex items-center justify-between gap-3">
                  <div>
                    <h2 class="text-lg font-semibold">Accordion</h2>
                    <p class="text-sm text-[var(--sd-muted-foreground)]">Detail panels for operational notes.</p>
                  </div>
                </div>

                <div class="mt-4 space-y-3">
                  <%= for item <- accordion_items() do %>
                    <details class="group rounded-[calc(var(--sd-radius)*1.4)] border border-[var(--sd-border)] bg-[var(--sd-panel)] p-4" open={item.open}>
                      <summary class="flex cursor-pointer items-center justify-between gap-4">
                        <span class="text-sm font-semibold">{item.title}</span>
                        <.icon name="hero-chevron-down" class="size-4 text-[var(--sd-muted-foreground)] transition group-open:rotate-180" />
                      </summary>
                      <p class="mt-3 text-sm leading-6 text-[var(--sd-muted-foreground)]">{item.body}</p>
                    </details>
                  <% end %>
                </div>
              </article>

              <article class="rounded-[calc(var(--sd-radius)*1.8)] border border-[var(--sd-border)] bg-[var(--sd-card)] p-5 shadow-[var(--sd-shadow-md)]">
                <div class="flex items-center justify-between gap-3">
                  <div>
                    <h2 class="text-lg font-semibold">Activity Toast</h2>
                    <p class="text-sm text-[var(--sd-muted-foreground)]">Floating notification preview.</p>
                  </div>
                </div>

                <div class="mt-4 rounded-[calc(var(--sd-radius)*1.6)] border border-[var(--sd-border)] bg-[var(--sd-panel)] p-4 shadow-[var(--sd-shadow-lg)]">
                  <div class="flex items-start gap-3">
                    <div class="rounded-full bg-emerald-500/15 p-2 text-emerald-600 dark:text-emerald-300">
                      <.icon name="hero-check-circle" class="size-5" />
                    </div>
                    <div class="min-w-0 flex-1">
                      <p class="text-sm font-semibold">Invoice accepted by provider</p>
                      <p class="mt-1 text-sm text-[var(--sd-muted-foreground)]">
                        E310000000412 moved to delivered state and was mirrored back to Odoo.
                      </p>
                    </div>
                    <button class="rounded-[var(--sd-radius)] p-1 text-[var(--sd-muted-foreground)] transition hover:bg-[var(--sd-muted)] hover:text-[var(--sd-foreground)]">
                      <.icon name="hero-x-mark" class="size-4" />
                    </button>
                  </div>
                </div>
              </article>
            </section>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :value, :string, required: true
  attr :detail, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <article class="rounded-[calc(var(--sd-radius)*1.8)] border border-[var(--sd-border)] bg-[var(--sd-card)] p-5 shadow-[var(--sd-shadow-md)]">
      <div class="flex items-center justify-between gap-3">
        <span class="inline-flex size-11 items-center justify-center rounded-[calc(var(--sd-radius)*1.2)] bg-[var(--sd-muted)] text-[var(--sd-primary)]">
          <.icon name={@icon} class="size-5" />
        </span>
        <span class="text-xs font-medium text-[var(--sd-muted-foreground)]">Live</span>
      </div>
      <p class="mt-4 text-sm text-[var(--sd-muted-foreground)]">{@title}</p>
      <p class="mt-1 text-3xl font-semibold tracking-[-0.04em]">{@value}</p>
      <p class="mt-2 text-xs leading-5 text-[var(--sd-muted-foreground)]">{@detail}</p>
    </article>
    """
  end

  attr :initials, :string, required: true
  attr :accent, :string, required: true

  defp theme_avatar(assigns) do
    ~H"""
    <div class={[
      "inline-flex size-11 items-center justify-center rounded-full border-2 border-[var(--sd-card)] text-sm font-semibold shadow-[var(--sd-shadow-sm)]",
      @accent
    ]}>
      {@initials}
    </div>
    """
  end

  defp demo_form do
    to_form(
      %{
        "company" => "Northwind Dominicana",
        "email" => "ops@northwind.do",
        "document" => "E310000000412",
        "queue" => "Priority",
        "notes" => "Escalate only if provider callback exceeds 30 seconds.",
        "notify" => "true",
        "archive" => "false"
      },
      as: :demo
    )
  end

  defp normalize_theme(theme) when theme in @theme_ids, do: theme
  defp normalize_theme(_theme), do: "clean-slate"

  defp theme_name(id) do
    @themes
    |> Enum.find(&(&1.id == id))
    |> then(fn
      nil -> "Clean Slate"
      theme -> theme.name
    end)
  end

  defp status_class("Delivered"),
    do: "bg-emerald-500/10 text-emerald-700 dark:text-emerald-300"

  defp status_class("Review"),
    do: "bg-amber-500/15 text-amber-700 dark:text-amber-300"

  defp status_class("Retrying"),
    do: "bg-rose-500/10 text-rose-700 dark:text-rose-300"

  defp transaction_rows do
    [
      %{document: "E310000000412", type: "Fiscal Credit", company: "Northwind", status: "Delivered", latency: "83ms"},
      %{document: "E320000000108", type: "Consumer Invoice", company: "Caribe Labs", status: "Review", latency: "142ms"},
      %{document: "E410000000067", type: "Debit Note", company: "Atlas Cargo", status: "Retrying", latency: "1.2s"},
      %{document: "E440000000219", type: "Export Invoice", company: "Boreal Trade", status: "Delivered", latency: "91ms"}
    ]
  end

  defp calendar_days do
    [
      %{label: "1", state: :plain},
      %{label: "2", state: :plain},
      %{label: "3", state: :plain},
      %{label: "4", state: :plain},
      %{label: "5", state: :accent},
      %{label: "6", state: :range},
      %{label: "7", state: :range},
      %{label: "8", state: :range},
      %{label: "9", state: :range},
      %{label: "10", state: :range},
      %{label: "11", state: :range},
      %{label: "12", state: :range},
      %{label: "13", state: :accent},
      %{label: "14", state: :plain},
      %{label: "15", state: :plain},
      %{label: "16", state: :plain},
      %{label: "17", state: :plain},
      %{label: "18", state: :plain},
      %{label: "19", state: :plain},
      %{label: "20", state: :plain},
      %{label: "21", state: :plain},
      %{label: "22", state: :plain},
      %{label: "23", state: :plain},
      %{label: "24", state: :plain},
      %{label: "25", state: :plain},
      %{label: "26", state: :plain},
      %{label: "27", state: :plain},
      %{label: "28", state: :plain},
      %{label: "29", state: :plain},
      %{label: "30", state: :plain},
      %{label: "1", state: :muted},
      %{label: "2", state: :muted},
      %{label: "3", state: :muted},
      %{label: "4", state: :muted},
      %{label: "5", state: :muted}
    ]
  end

  defp review_queue do
    [
      %{title: "Missing provider acknowledgment", meta: "Boreal Trade · 2 minutes ago", label: "Attention"},
      %{title: "Duplicate RNC detected in import batch", meta: "Northwind · 7 minutes ago", label: "Review"},
      %{title: "Manual tax code override requested", meta: "Atlas Cargo · 15 minutes ago", label: "Pending"}
    ]
  end

  defp accordion_items do
    [
      %{
        title: "Why use URL-based theme selection?",
        body: "It keeps the page shareable and LiveView-friendly while avoiding extra client state plumbing.",
        open: true
      },
      %{
        title: "How are the themes applied?",
        body: "The page sets a `data-shadcn-theme` attribute and CSS variables map the clean-slate and graphite registry values into reusable tokens.",
        open: false
      },
      %{
        title: "What makes this Phoenix-safe?",
        body: "Everything is standard HEEx and Tailwind classes. No React runtime, no npm packages, and no compilation was triggered.",
        open: false
      }
    ]
  end
end
