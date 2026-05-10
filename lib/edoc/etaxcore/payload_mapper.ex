defmodule Edoc.Etaxcore.PayloadMapper do
  @moduledoc """
  Mapping entrypoint for supported Odoo invoice payloads.
  """

  alias Edoc.Accounts.Company
  alias Edoc.Etaxcore.E31Pipeline
  alias Edoc.Etaxcore.E32Pipeline
  alias Edoc.Etaxcore.E41Pipeline
  alias Edoc.Etaxcore.E43Pipeline
  alias Edoc.Etaxcore.E47Pipeline

  @spec map_e31(map(), Company.t(), keyword()) :: map()
  def map_e31(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    E31Pipeline.map(payload, company, opts)
  end

  @spec map_e32(map(), Company.t(), keyword()) :: map()
  def map_e32(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    E32Pipeline.map(payload, company, opts)
  end

  @spec map_e41(map(), Company.t(), keyword()) :: map()
  def map_e41(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    E41Pipeline.map(payload, company, opts)
  end

  @spec map_e43(map(), Company.t(), keyword()) :: map()
  def map_e43(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    E43Pipeline.map(payload, company, opts)
  end

  @spec map_e47(map(), Company.t(), keyword()) :: map()
  def map_e47(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    E47Pipeline.map(payload, company, opts)
  end

  @spec map_invoice(map(), Company.t(), keyword()) :: map()
  def map_invoice(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    e_doc = generated_edoc!(opts)

    opts = Keyword.put(opts, :e_doc, e_doc)

    case parse_tipo_ecf(e_doc) do
      31 ->
        map_e31(payload, company, opts)

      32 ->
        map_e32(payload, company, opts)

      41 ->
        map_e41(payload, company, opts)

      43 ->
        map_e43(payload, company, opts)

      47 ->
        map_e47(payload, company, opts)

      nil ->
        raise ArgumentError, "invalid generated e_doc for encf"

      tipo_ecf ->
        raise ArgumentError,
              "unsupported eCF type E#{tipo_ecf}; only E31/E32/E41/E43/E47 are enabled"
    end
  end

  defp generated_edoc!(opts) do
    case Keyword.get(opts, :e_doc) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> raise ArgumentError, "missing generated e_doc for encf"
          e_doc -> e_doc
        end

      _value ->
        raise ArgumentError, "missing generated e_doc for encf"
    end
  end

  defp parse_tipo_ecf(value) when is_binary(value) do
    case Regex.run(~r/^E?(\d{2})/, String.trim(value)) do
      [_, digits] -> String.to_integer(digits)
      _ -> nil
    end
  end

  defp parse_tipo_ecf(_value), do: nil
end
