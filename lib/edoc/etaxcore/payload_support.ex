defmodule Edoc.Etaxcore.PayloadSupport do
  @moduledoc """
  Shared helpers for eTaxCore payload pipelines.
  """

  @spec document_currency_payload(map()) :: map()
  def document_currency_payload(payload) when is_map(payload) do
    payload
    |> put_document_amount("amount_untaxed", "base_amount_currency")
    |> put_document_amount("amount_tax", "tax_amount_currency")
    |> put_document_amount("amount_total", "total_amount_currency")
    |> put_in_tax_totals_currency()
    |> Map.put("tipo_cambio", 1)
    |> Map.put("tipoCambio", 1)
    |> Map.put("exchange_rate", 1)
  end

  @spec normalize_currency_fields(term(), MapSet.t()) :: term()
  def normalize_currency_fields(%{} = payload, currency_fields) do
    Map.new(payload, fn {key, value} ->
      normalized_value =
        if MapSet.member?(currency_fields, key) do
          format_currency(value)
        else
          normalize_currency_fields(value, currency_fields)
        end

      {key, normalized_value}
    end)
  end

  def normalize_currency_fields(value, currency_fields) when is_list(value) do
    Enum.map(value, &normalize_currency_fields(&1, currency_fields))
  end

  def normalize_currency_fields(value, _currency_fields), do: value

  @spec format_currency(term()) :: term()
  def format_currency(value) do
    case Decimal.cast(value) do
      {:ok, decimal} ->
        decimal
        |> Decimal.round(2, :down)
        |> Decimal.to_string(:normal)
        |> pad_currency_decimals()

      :error ->
        value
    end
  end

  @spec numeric(term()) :: number() | nil
  def numeric(nil), do: nil
  def numeric(value) when is_integer(value) or is_float(value), do: value
  def numeric(%Decimal{} = value), do: Decimal.to_float(value)

  def numeric(value) when is_binary(value) do
    trimmed = String.trim(value)

    case Integer.parse(trimmed) do
      {int, ""} ->
        int

      _ ->
        case Float.parse(trimmed) do
          {float, ""} -> float
          _ -> nil
        end
    end
  end

  def numeric(_value), do: nil

  @spec payload_value(map(), atom() | String.t()) :: term()
  def payload_value(%{} = payload, key) when is_atom(key) do
    Map.get(payload, key) || Map.get(payload, Atom.to_string(key))
  end

  def payload_value(%{} = payload, key) when is_binary(key), do: Map.get(payload, key)
  def payload_value(_payload, _key), do: nil

  @spec value_from_keys(map(), [atom() | String.t()]) :: term()
  def value_from_keys(payload, keys) when is_map(payload) and is_list(keys) do
    Enum.find_value(keys, &payload_value(payload, &1))
  end

  def value_from_keys(_payload, _keys), do: nil

  @spec zero_amount?(term()) :: boolean()
  def zero_amount?(value) when value in [0, 0.0], do: true
  def zero_amount?(value) when is_number(value), do: abs(value) < 0.000001
  def zero_amount?(_value), do: false

  defp put_document_amount(payload, target_key, source_key) do
    case tax_totals_value(payload, source_key) do
      nil -> payload
      amount -> Map.put(payload, target_key, amount)
    end
  end

  defp put_in_tax_totals_currency(payload) do
    case payload_value(payload, "tax_totals") do
      %{} = tax_totals ->
        Map.put(payload, "tax_totals", currency_tax_totals(tax_totals))

      _other ->
        payload
    end
  end

  defp currency_tax_totals(tax_totals) do
    tax_totals
    |> copy_amount("base_amount", "base_amount_currency")
    |> copy_amount("tax_amount", "tax_amount_currency")
    |> copy_amount("total_amount", "total_amount_currency")
    |> Map.update("subtotals", [], fn subtotals ->
      Enum.map(List.wrap(subtotals), fn subtotal ->
        subtotal
        |> copy_amount("base_amount", "base_amount_currency")
        |> copy_amount("tax_amount", "tax_amount_currency")
        |> Map.update("tax_groups", [], fn tax_groups ->
          Enum.map(List.wrap(tax_groups), fn tax_group ->
            tax_group
            |> copy_amount("base_amount", "base_amount_currency")
            |> copy_amount("display_base_amount", "display_base_amount_currency")
            |> copy_amount("tax_amount", "tax_amount_currency")
          end)
        end)
      end)
    end)
  end

  defp copy_amount(map, target_key, source_key) do
    case numeric(Map.get(map, source_key)) do
      nil -> map
      amount -> Map.put(map, target_key, amount)
    end
  end

  defp tax_totals_value(payload, key) do
    payload
    |> payload_value("tax_totals")
    |> case do
      %{} = totals -> numeric(Map.get(totals, key))
      _other -> nil
    end
  end

  defp pad_currency_decimals(value) do
    case String.split(value, ".", parts: 2) do
      [whole, fraction] ->
        "#{whole}.#{String.pad_trailing(String.slice(fraction, 0, 2), 2, "0")}"

      [whole] ->
        "#{whole}.00"
    end
  end
end
