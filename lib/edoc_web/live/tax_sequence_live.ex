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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-2xl mx-auto px-4 py-6 space-y-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-semibold text-white">Tax sequences</h1>
            <p class="text-sm text-zinc-500">
              Update the DGII label, prefix, and suffix baseline with the same simple flow as creating a company.
            </p>
          </div>
          <span class="badge badge-outline">{length(@tax_sequences)} total</span>
        </div>

        <%= if Enum.empty?(@tax_sequences) do %>
          <p class="rounded-lg border border-dashed border-zinc-800 px-4 py-6 text-center text-sm text-zinc-400">
            No sequences available. Seed them before editing.
          </p>
        <% else %>
          <.form
            for={%{}}
            id="tax-sequence-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-6 rounded-xl border border-zinc-800 bg-base-100/80 p-5 shadow-lg"
          >
            <div class="space-y-5">
              <%= for sequence <- @tax_sequences do %>
                <div class="rounded-lg border border-zinc-800/60 p-4">
                  <div class="flex items-center justify-between text-sm text-zinc-400">
                    <p class="font-semibold text-base-content">{sequence.label}</p>
                    <span class="badge badge-neutral">{sequence.prefix}</span>
                  </div>
                  <div class="mt-4">
                    <label class="text-xs font-semibold uppercase tracking-wide text-zinc-500">
                      START SEQUENCE
                    </label>
                    <input
                      type="number"
                      name={"sequences[#{sequence.id}][suffix]"}
                      value={
                        @tax_sequences_changes && Map.get(@tax_sequences_changes, sequence.id) ||
                          sequence.suffix || 0
                      }
                      min="0"
                      step="1"
                      class={[
                        "input input-bordered mt-1 w-full font-mono",
                        Map.has_key?(@tax_sequences_errors || %{}, sequence.id) && "input-error"
                      ]}
                    />
                    <p :if={reason = Map.get(@tax_sequences_errors || %{}, sequence.id)} class="mt-1 text-xs text-error">
                      {reason}
                    </p>
                  </div>
                </div>
              <% end %>
            </div>

            <div class="flex items-center gap-3 pt-2">
              <.button type="submit">Save</.button>
            </div>
          </.form>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

end
