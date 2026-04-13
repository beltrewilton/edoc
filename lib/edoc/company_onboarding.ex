defmodule Edoc.CompanyOnboarding do
  @moduledoc """
  Validation helpers for the multi-step company onboarding flow.
  """

  alias Edoc.Accounts.Company

  @spec lookup_rnc(String.t()) :: {:ok, Edoc.DgiiRncScraper.Result.t()} | {:error, term()}
  def lookup_rnc(rnc) when is_binary(rnc) do
    dgii_lookup_client().lookup(rnc)
  end

  @spec validate_odoo(map() | Company.t()) :: {:ok, map()} | {:error, String.t()}
  def validate_odoo(attrs) when is_map(attrs) do
    odoo_validation_client().validate_odoo(attrs)
  end

  @spec validate_provider(map() | Company.t()) :: {:ok, map()} | {:error, String.t()}
  def validate_provider(attrs) when is_map(attrs) do
    provider_validation_client().validate_provider(attrs)
  end

  defp dgii_lookup_client do
    Application.get_env(:edoc, :dgii_lookup_client, Edoc.DgiiRncScraper)
  end

  defp odoo_validation_client do
    Application.get_env(:edoc, :odoo_validation_client, Edoc.CompanyOnboarding.OdooValidation)
  end

  defp provider_validation_client do
    Application.get_env(
      :edoc,
      :provider_validation_client,
      Edoc.CompanyOnboarding.ProviderValidation
    )
  end
end
