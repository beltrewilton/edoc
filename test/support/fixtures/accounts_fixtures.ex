defmodule Edoc.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Edoc.Accounts` context.
  """

  import Ecto.Query

  alias Edoc.Accounts
  alias Edoc.Accounts.Scope
  alias Edoc.Repo
  alias Edoc.TenantContext
  alias Edoc.Transaction
  alias Ecto.Adapters.SQL.Sandbox

  require Logger

  alias Triplex

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email()
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)

    token =
      extract_user_token(fn url ->
        Accounts.deliver_login_instructions(user, url)
      end)

    {:ok, {user, _expired_tokens}} =
      Accounts.login_user_by_magic_link(token)

    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Edoc.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    Edoc.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Edoc.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end

  def tenant_fixture(opts \\ []) do
    tenant = opts[:tenant] || "tenant_#{System.unique_integer([:positive])}"

    :ok =
      Sandbox.unboxed_run(Repo, fn ->
        case Triplex.create(tenant, Repo) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.error("Failed to create tenant #{tenant}: #{inspect(reason)}")
            raise "unable to create tenant #{tenant}"
        end
      end)

    tenant
  end

  def company_fixture(%Scope{} = scope, attrs \\ %{}) do
    default_attrs = %{
      "company_name" => "Acme #{System.unique_integer([:positive])}",
      "rnc" => "RNC#{System.unique_integer([:positive])}",
      "odoo_url" => "https://odoo.example.com/#{System.unique_integer([:positive])}",
      "odoo_db" => "db_#{System.unique_integer([:positive])}",
      "odoo_user" => "user#{System.unique_integer([:positive])}@example.com",
      "odoo_apikey" => "apikey-#{System.unique_integer([:positive])}"
    }

    attrs = Map.merge(default_attrs, stringify_keys(attrs))

    {:ok, company} = Accounts.create_company(scope, attrs)
    company
  end

  def transaction_fixture(%{id: company_id}, attrs \\ %{}) do
    tenant = TenantContext.get_tenant()

    default_request = %{
      "rnc" => "131941968",
      "e_doc" => "E-DOC-#{System.unique_integer([:positive])}",
      "amount" => 1250.5,
      "tax" => 112.5
    }

    overrides =
      %{
        "rnc" => fetch_attr(attrs, :rnc),
        "e_doc" => fetch_attr(attrs, :e_doc),
        "amount" => fetch_attr(attrs, :amount),
        "tax" => fetch_attr(attrs, :tax)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    odoo_request =
      default_request
      |> Map.merge(fetch_attr(attrs, :odoo_request) || %{})
      |> Map.merge(overrides)

    params = %Transaction{
      company_id: company_id,
      odoo_request: odoo_request,
      provider_request: fetch_attr(attrs, :provider_request) || %{},
      provider_response: fetch_attr(attrs, :provider_response) || %{},
      odoo_request_at: fetch_attr(attrs, :odoo_request_at) || DateTime.utc_now(:second),
      provider_request_at: fetch_attr(attrs, :provider_request_at),
      provider_response_at: fetch_attr(attrs, :provider_response_at)
    }

    Repo.insert!(params, prefix: tenant)
  end

  defp fetch_attr(attrs, key) when is_atom(key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp fetch_attr(attrs, key) when is_binary(key) do
    Map.get(attrs, key)
  end

  defp fetch_attr(_, _), do: nil

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {key, value}
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
    end)
  end

  defp stringify_keys(other), do: other
end
