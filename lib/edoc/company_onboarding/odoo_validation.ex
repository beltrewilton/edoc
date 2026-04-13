defmodule Edoc.CompanyOnboarding.OdooValidation do
  @moduledoc """
  Connectivity validation for Odoo credentials collected during company onboarding.
  """

  alias Edoc.Accounts.Company
  alias Edoc.OdooAutomationClient, as: Odoo

  @spec validate_odoo(map() | Company.t()) :: {:ok, map()} | {:error, String.t()}
  def validate_odoo(%Company{} = company) do
    company
    |> Odoo.new()
    |> authenticate()
  end

  def validate_odoo(attrs) when is_map(attrs) do
    attrs
    |> company_from_attrs()
    |> validate_odoo()
  end

  defp authenticate(client) do
    try do
      uid = Odoo.authenticate!(client)
      {:ok, %{message: "Odoo connection validated.", uid: uid}}
    rescue
      error -> {:error, Exception.message(error)}
    end
  end

  defp company_from_attrs(attrs) do
    %Company{
      odoo_url: fetch_value(attrs, "odoo_url"),
      odoo_db: fetch_value(attrs, "odoo_db"),
      odoo_user: fetch_value(attrs, "odoo_user"),
      odoo_apikey: fetch_value(attrs, "odoo_apikey")
    }
  end

  defp fetch_value(attrs, key) when is_binary(key) do
    Map.get(attrs, key) || Map.get(attrs, String.to_existing_atom(key))
  end
end
