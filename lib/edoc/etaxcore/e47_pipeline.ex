defmodule Edoc.Etaxcore.E47Pipeline do
  @moduledoc """
  E47 mapper for Odoo invoice payloads.
  """

  alias Edoc.Accounts.Company
  alias Edoc.Etaxcore.E41E47Pipeline

  @spec map(map(), Company.t(), keyword()) :: map()
  def map(payload, %Company{} = company, opts \\ []) when is_map(payload) do
    E41E47Pipeline.map(payload, company, 47, opts)
  end
end
