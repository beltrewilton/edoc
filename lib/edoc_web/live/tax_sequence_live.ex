defmodule EdocWeb.TaxSequenceLive do
  use EdocWeb, :live_view

  alias Edoc.Accounts

  @impl true
  def mount(_params, _session, socket) do
    sequences = Accounts.list_tax_sequences()

    socket =
      socket
      |> assign(:page_title, "DGII Tax Sequences")
      |> assign(:tax_sequences, sequences)
      |> assign(:tax_sequences_changes, %{})
      |> assign(:tax_sequences_errors, %{})

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", params, socket) do
    socket = validate_suffixes(socket, params)
    {:noreply, socket}
  end

  def handle_event("save", params, socket) do
    socket = validate_suffixes(socket, params)

    case upsert_suffixes(socket.assigns.tax_sequences_changes) do
      :ok ->
        sequences = Accounts.list_tax_sequences()

        {:noreply,
         socket
         |> assign(:tax_sequences, sequences)
         |> assign(:tax_sequences_changes, %{})
         |> assign(:tax_sequences_errors, %{})
         |> put_flash(:info, "Sequences updated successfully")}

      {:error, errors} ->
        {:noreply, assign(socket, :tax_sequences_errors, errors)}
    end
  end

  defp validate_suffixes(socket, %{"sequences" => seq_params}) do
    changes =
      seq_params
      |> Enum.reduce(%{}, fn {id, attrs}, acc ->
        with %{"suffix" => suffix} <- attrs,
             {:ok, suffix_int} <- parse_suffix(suffix) do
          Map.put(acc, id, suffix_int)
        else
          _ -> acc
        end
      end)

    errors =
      seq_params
      |> Enum.reduce(%{}, fn {id, attrs}, acc ->
        with %{"suffix" => suffix} <- attrs,
             {:ok, _} <- parse_suffix(suffix) do
          acc
        else
          {:error, reason} -> Map.put(acc, id, reason)
          _ -> acc
        end
      end)

    socket
    |> assign(:tax_sequences_changes, changes)
    |> assign(:tax_sequences_errors, errors)
  end

  defp validate_suffixes(socket, _params), do: socket

  defp upsert_suffixes(changes) when map_size(changes) == 0, do: :ok

  defp upsert_suffixes(changes) do
    errors =
      Enum.reduce_while(changes, %{}, fn {id, suffix}, acc ->
        sequence = Accounts.get_tax_sequence!(id)

        case Accounts.update_tax_sequence(sequence, %{"suffix" => suffix}) do
          {:ok, _} -> {:cont, acc}
          {:error, %Ecto.Changeset{} = changeset} -> {:halt, Map.put(acc, id, changeset.errors)}
        end
      end)

    if map_size(errors) == 0, do: :ok, else: {:error, errors}
  end

  defp parse_suffix(""), do: {:error, "Suffix can't be blank"}

  defp parse_suffix(value) do
    case Integer.parse(value) do
      {val, ""} when val >= 0 -> {:ok, val}
      {val, ""} when val < 0 -> {:error, "Suffix must be >= 0"}
      _ -> {:error, "Suffix must be a number"}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <div class="mx-auto w-full max-w-3xl space-y-5">
        <.header>
          Tax Sequences
          <:subtitle>Maintain DGII labels, prefixes, and suffix baselines.</:subtitle>
          <:actions>
            <span class="inline-flex rounded-full border border-slate-200 bg-slate-100 px-3 py-1 text-xs font-semibold text-slate-700 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-300">
              {length(@tax_sequences)} total
            </span>
          </:actions>
        </.header>

        <%= if Enum.empty?(@tax_sequences) do %>
          <.surface>
            <p class="rounded-xl border border-dashed border-slate-300 px-4 py-8 text-center text-sm text-slate-500 dark:border-slate-700 dark:text-slate-400">
              No sequences available. Seed them before editing.
            </p>
          </.surface>
        <% else %>
          <.surface>
            <.form
              for={%{}}
              id="tax-sequence-form"
              phx-change="validate"
              phx-submit="save"
              class="space-y-5"
            >
              <%= for sequence <- @tax_sequences do %>
                <div class="rounded-xl border border-slate-200 p-4 dark:border-slate-800">
                  <div class="flex items-center justify-between">
                    <p class="text-sm font-semibold text-slate-900 dark:text-slate-100">{sequence.label}</p>
                    <span class="inline-flex rounded-full border border-slate-200 bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-700 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-300">
                      {sequence.prefix}
                    </span>
                  </div>

                  <% error = Map.get(@tax_sequences_errors || %{}, sequence.id) %>
                  <div class="mt-4">
                    <.input
                      type="number"
                      id={"sequence-#{sequence.id}-suffix"}
                      name={"sequences[#{sequence.id}][suffix]"}
                      value={
                        @tax_sequences_changes && Map.get(@tax_sequences_changes, sequence.id) ||
                          sequence.suffix || 0
                      }
                      min="0"
                      step="1"
                      label="Start sequence"
                      errors={if(error, do: [error], else: [])}
                    />
                  </div>
                </div>
              <% end %>

              <div class="flex items-center gap-3 pt-1">
                <.button type="submit">Save changes</.button>
              </div>
            </.form>
          </.surface>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

end
