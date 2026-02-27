defmodule EdocWeb.CoreComponents do
  @moduledoc """
  Provides shared UI components for the application.
  """
  use Phoenix.Component
  use Gettext, backend: EdocWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Shared design recipes used across the app.
  """
  @spec ui(atom()) :: String.t()
  def ui(:page_bg),
    do:
      "bg-slate-100 text-slate-900 dark:bg-[#070d19] dark:text-slate-100"

  def ui(:shell),
    do:
      "rounded-3xl border border-slate-200/80 bg-white/95 shadow-[0_25px_80px_-40px_rgba(15,23,42,0.35)] backdrop-blur dark:border-slate-800/80 dark:bg-[#0f172a]/95 dark:shadow-[0_35px_100px_-45px_rgba(2,6,23,0.95)]"

  def ui(:card),
    do:
      "rounded-2xl border border-slate-200/80 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900/70 dark:shadow-black/25"

  def ui(:card_header),
    do:
      "border-b border-slate-200/80 px-5 py-4 dark:border-slate-800"

  def ui(:table),
    do:
      "overflow-hidden rounded-2xl border border-slate-200/80 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900/70"

  def ui(:input),
    do:
      "block w-full rounded-xl border border-slate-200 bg-white px-3.5 py-2.5 text-sm text-slate-900 shadow-sm outline-none transition placeholder:text-slate-400 focus:border-indigo-400 focus:ring-2 focus:ring-indigo-200 dark:border-slate-700 dark:bg-slate-900/80 dark:text-slate-100 dark:placeholder:text-slate-500 dark:focus:border-indigo-500 dark:focus:ring-indigo-500/25"

  def ui(:btn_primary),
    do:
      "border border-transparent bg-indigo-600 text-white hover:bg-indigo-500 focus-visible:ring-indigo-400"

  def ui(:btn_secondary),
    do:
      "border border-slate-200 bg-white text-slate-700 hover:bg-slate-50 hover:border-slate-300 focus-visible:ring-slate-300 dark:border-slate-700 dark:bg-slate-900/70 dark:text-slate-200 dark:hover:bg-slate-800"

  def ui(:btn_ghost),
    do:
      "border border-transparent text-slate-600 hover:bg-slate-100 hover:text-slate-900 focus-visible:ring-slate-300 dark:text-slate-300 dark:hover:bg-slate-800/80 dark:hover:text-slate-100"

  def ui(:btn_danger),
    do:
      "border border-transparent bg-rose-600 text-white hover:bg-rose-500 focus-visible:ring-rose-300"

  def ui(:tile),
    do:
      "group flex h-full flex-col rounded-2xl border border-slate-200 bg-white p-4 shadow-sm transition duration-200 hover:-translate-y-0.5 hover:border-indigo-300 hover:shadow-lg dark:border-slate-800 dark:bg-slate-900/70 dark:hover:border-indigo-500/60 dark:hover:bg-slate-900"

  @doc """
  Renders flash notices.
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="pointer-events-auto w-full max-w-sm"
      {@rest}
    >
      <div class={[
        "flex items-start gap-3 rounded-xl border px-4 py-3 shadow-lg backdrop-blur transition",
        @kind == :info &&
          "border-indigo-200 bg-indigo-50 text-indigo-900 dark:border-indigo-500/40 dark:bg-indigo-500/15 dark:text-indigo-100",
        @kind == :error &&
          "border-rose-200 bg-rose-50 text-rose-900 dark:border-rose-500/40 dark:bg-rose-500/15 dark:text-rose-100"
      ]}>
        <.icon
          :if={@kind == :info}
          name="hero-information-circle"
          class="mt-0.5 size-5 shrink-0 text-indigo-500 dark:text-indigo-300"
        />
        <.icon
          :if={@kind == :error}
          name="hero-exclamation-circle"
          class="mt-0.5 size-5 shrink-0 text-rose-500 dark:text-rose-300"
        />
        <div class="min-w-0 flex-1">
          <p :if={@title} class="font-semibold">{@title}</p>
          <p class="text-sm">{msg}</p>
        </div>
        <button type="button" class="group mt-0.5 cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-50 transition group-hover:opacity-90" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with optional navigation support.
  """
  attr :rest, :global,
    include:
      ~w(href navigate patch method download name value disabled phx-click phx-value-id phx-disable-with)

  attr :class, :string, default: nil
  attr :variant, :string, values: ~w(primary secondary ghost danger), default: "primary"
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    base_class =
      "inline-flex items-center justify-center gap-2 rounded-xl px-4 py-2 text-sm font-semibold transition duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-offset-white disabled:cursor-not-allowed disabled:opacity-60 dark:focus-visible:ring-offset-slate-950"

    variant_class =
      case assigns.variant do
        "secondary" -> ui(:btn_secondary)
        "ghost" -> ui(:btn_ghost)
        "danger" -> ui(:btn_danger)
        _ -> ui(:btn_primary)
      end

    assigns = assign(assigns, :button_class, [base_class, variant_class, assigns.class])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@button_class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@button_class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="space-y-1.5">
      <label
        for={@id}
        class="inline-flex items-center gap-3 text-sm font-medium text-slate-700 dark:text-slate-300"
      >
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={[
            @class ||
              "size-4 rounded border-slate-300 text-indigo-600 focus:ring-indigo-400 dark:border-slate-700 dark:bg-slate-900",
            @errors != [] && (@error_class || "border-rose-300 ring-rose-100")
          ]}
          {@rest}
        />
        <span :if={@label}>{@label}</span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="space-y-1.5">
      <label
        :if={@label}
        for={@id}
        class="block text-xs font-semibold uppercase tracking-[0.2em] text-slate-500 dark:text-slate-400"
      >
        {@label}
      </label>
      <select
        id={@id}
        name={@name}
        class={[
          @class || ui(:input),
          @errors != [] &&
            (@error_class ||
               "border-rose-300 focus:border-rose-300 focus:ring-rose-100 dark:border-rose-500/70")
        ]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="space-y-1.5">
      <label
        :if={@label}
        for={@id}
        class="block text-xs font-semibold uppercase tracking-[0.2em] text-slate-500 dark:text-slate-400"
      >
        {@label}
      </label>
      <textarea
        id={@id}
        name={@name}
        class={[
          @class || ui(:input),
          @errors != [] &&
            (@error_class ||
               "border-rose-300 focus:border-rose-300 focus:ring-rose-100 dark:border-rose-500/70")
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class="space-y-1.5">
      <label
        :if={@label}
        for={@id}
        class="block text-xs font-semibold uppercase tracking-[0.2em] text-slate-500 dark:text-slate-400"
      >
        {@label}
      </label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          @class || ui(:input),
          @errors != [] &&
            (@error_class ||
               "border-rose-300 focus:border-rose-300 focus:ring-rose-100 dark:border-rose-500/70")
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  slot :inner_block, required: true

  defp error(assigns) do
    ~H"""
    <p class="flex items-center gap-1.5 text-xs font-medium text-rose-600 dark:text-rose-300">
      <.icon name="hero-exclamation-circle" class="size-4" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title, subtitle, and optional actions.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[
      "pb-4",
      @actions != [] && "flex items-start justify-between gap-4"
    ]}>
      <div class="min-w-0">
        <h1 class="text-2xl font-semibold tracking-tight text-slate-900 dark:text-slate-100">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-1 text-sm text-slate-500 dark:text-slate-400">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div :if={@actions != []} class="shrink-0">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.
  """
  attr :id, :string, required: true
  attr :rows, :any, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class={ui(:table)}>
      <table class="min-w-full divide-y divide-slate-200 dark:divide-slate-800">
        <thead class="bg-slate-50 dark:bg-slate-900/80">
          <tr>
            <th
              :for={col <- @col}
              class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-[0.18em] text-slate-500 dark:text-slate-400"
            >
              {col[:label]}
            </th>
            <th :if={@action != []} class="px-4 py-3 text-right">
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}
          class="divide-y divide-slate-100 dark:divide-slate-800"
        >
          <tr
            :for={row <- @rows}
            id={@row_id && @row_id.(row)}
            class="transition hover:bg-slate-50/80 dark:hover:bg-slate-800/45"
          >
            <td
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={[
                "px-4 py-3 text-sm text-slate-700 dark:text-slate-200",
                @row_click && "cursor-pointer"
              ]}
            >
              {render_slot(col, @row_item.(row))}
            </td>
            <td :if={@action != []} class="px-4 py-3 text-right text-sm font-medium text-slate-700 dark:text-slate-200">
              <div class="inline-flex items-center gap-2">
                <%= for action <- @action do %>
                  {render_slot(action, @row_item.(row))}
                <% end %>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="space-y-3">
      <li :for={item <- @item} class={[ui(:card), "px-4 py-3"]}>
        <p class="text-xs font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">
          {item.title}
        </p>
        <div class="mt-1 text-sm text-slate-700 dark:text-slate-200">{render_slot(item)}</div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a neutral container surface.
  """
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def surface(assigns) do
    ~H"""
    <section class={[ui(:card), "p-5", @class]}>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  Renders a status pill.
  """
  attr :tone, :string, values: ~w(neutral success warning danger info), default: "neutral"
  slot :inner_block, required: true

  def status_pill(assigns) do
    tone_class =
      case assigns.tone do
        "success" ->
          "border-emerald-200 bg-emerald-50 text-emerald-700 dark:border-emerald-500/40 dark:bg-emerald-500/15 dark:text-emerald-300"

        "warning" ->
          "border-amber-200 bg-amber-50 text-amber-700 dark:border-amber-500/40 dark:bg-amber-500/15 dark:text-amber-300"

        "danger" ->
          "border-rose-200 bg-rose-50 text-rose-700 dark:border-rose-500/40 dark:bg-rose-500/15 dark:text-rose-300"

        "info" ->
          "border-indigo-200 bg-indigo-50 text-indigo-700 dark:border-indigo-500/40 dark:bg-indigo-500/15 dark:text-indigo-300"

        _ ->
          "border-slate-200 bg-slate-100 text-slate-700 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-300"
      end

    assigns = assign(assigns, :tone_class, tone_class)

    ~H"""
    <span class={[
      "inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-semibold",
      @tone_class
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  Renders a launcher module tile.
  """
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :icon, :string, required: true
  attr :href, :string, default: nil
  attr :locked, :boolean, default: false
  attr :tag, :string, default: nil
  attr :id, :string, default: nil

  def module_tile(assigns) do
    assigns =
      assign_new(assigns, :tile_class, fn ->
        [
          ui(:tile),
          assigns.locked &&
            "border-slate-200 bg-slate-50 text-slate-500 hover:translate-y-0 hover:border-slate-200 dark:border-slate-800 dark:bg-slate-900/40 dark:text-slate-400"
        ]
      end)

    ~H"""
    <.link :if={@href} id={@id} navigate={@href} class={@tile_class} aria-disabled={@locked}>
      <div class="flex items-start justify-between gap-3">
        <span class={[
          "inline-flex size-10 items-center justify-center rounded-xl",
          @locked && "bg-slate-200 text-slate-500 dark:bg-slate-800 dark:text-slate-400",
          !@locked && "bg-indigo-600 text-white shadow-[0_8px_24px_-12px_rgba(79,70,229,0.8)]"
        ]}>
          <.icon name={@icon} class="size-5" />
        </span>
        <div class="flex items-center gap-2">
          <span
            :if={@tag}
            class="inline-flex rounded-full border border-slate-200 bg-slate-100 px-2 py-0.5 text-[0.65rem] font-semibold uppercase tracking-wide text-slate-600 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-300"
          >
            {@tag}
          </span>
          <span
            :if={@locked}
            class="inline-flex items-center gap-1 rounded-full border border-amber-200 bg-amber-50 px-2 py-0.5 text-[0.65rem] font-semibold uppercase tracking-wide text-amber-700 dark:border-amber-500/50 dark:bg-amber-500/15 dark:text-amber-300"
          >
            <.icon name="hero-lock-closed" class="size-3.5" /> Login
          </span>
        </div>
      </div>

      <p class="mt-4 text-sm font-semibold text-slate-900 group-hover:text-indigo-600 dark:text-slate-100 dark:group-hover:text-indigo-300">
        {@title}
      </p>
      <p :if={@description} class="mt-1 text-sm leading-5 text-slate-500 dark:text-slate-400">
        {@description}
      </p>
    </.link>

    <div :if={!@href} id={@id} class={@tile_class}>
      <div class="flex items-start justify-between gap-3">
        <span class="inline-flex size-10 items-center justify-center rounded-xl bg-indigo-600 text-white shadow-[0_8px_24px_-12px_rgba(79,70,229,0.8)]">
          <.icon name={@icon} class="size-5" />
        </span>
      </div>
      <p class="mt-4 text-sm font-semibold text-slate-900 dark:text-slate-100">{@title}</p>
      <p :if={@description} class="mt-1 text-sm leading-5 text-slate-500 dark:text-slate-400">
        {@description}
      </p>
    </div>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).
  """
  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(EdocWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(EdocWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
