defmodule Edoc.Etaxcore.E41Pipeline do
  @moduledoc """
  E41 mapper for Odoo invoice payloads.
  """

  alias Edoc.Accounts.Company
  alias Edoc.Etaxcore.E41E47Pipeline

  @spec map(map(), Company.t(), keyword()) :: map()
  def map(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    E41E47Pipeline.map(payload, company, 41, opts)
  end
end
