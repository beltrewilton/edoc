defmodule EdocWeb.CompanyLiveTest do
  use EdocWeb.ConnCase, async: false

  import Edoc.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Edoc.Accounts
  alias Edoc.Accounts.Scope
  alias Edoc.Repo
  alias Edoc.TenantContext
  alias Ecto.Adapters.SQL.Sandbox
  alias Triplex

  setup [:register_and_log_in_user]

  setup %{user: user} do
    tenant = tenant_fixture()

    {:ok, user} = Accounts.update_user_tenant(user, %{tenant: tenant})
    scope = Scope.for_user(user)

    TenantContext.put_tenant(tenant)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Triplex.drop(tenant, Repo)
      end)
    end)

    {:ok, %{tenant: tenant, scope: scope, user: user}}
  end

  setup do
    old_dgii = Application.get_env(:edoc, :dgii_lookup_client)
    old_odoo = Application.get_env(:edoc, :odoo_validation_client)
    old_provider = Application.get_env(:edoc, :provider_validation_client)
    old_results = Application.get_env(:edoc, :company_onboarding_test_results)

    Application.put_env(:edoc, :dgii_lookup_client, Edoc.TestSupport.CompanyOnboardingStub)
    Application.put_env(:edoc, :odoo_validation_client, Edoc.TestSupport.CompanyOnboardingStub)
    Application.put_env(:edoc, :provider_validation_client, Edoc.TestSupport.CompanyOnboardingStub)
    Application.put_env(:edoc, :company_onboarding_test_results, %{})

    on_exit(fn ->
      restore_env(:dgii_lookup_client, old_dgii)
      restore_env(:odoo_validation_client, old_odoo)
      restore_env(:provider_validation_client, old_provider)
      restore_env(:company_onboarding_test_results, old_results)
    end)

    :ok
  end

  describe "new company" do
    test "starts with the DGII lookup step only", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/companies/new")

      assert has_element?(lv, "#company-step-1-form input[name=\"company[rnc]\"]")
      refute has_element?(lv, "#company-step-1-form input[name=\"company[provider_endpoint]\"]")
      refute has_element?(lv, "#company-step-2-form")
    end

    test "creates a company only after DGII, Odoo, and provider validation", %{
      conn: conn,
      scope: scope
    } do
      {:ok, lv, _html} = live(conn, ~p"/companies/new")

      lv
      |> form("#company-step-1-form", company: %{"rnc" => "132190068"})
      |> render_submit()

      assert has_element?(lv, "#company-step-2-form")

      lv
      |> form("#company-step-2-form",
        company: %{
          "odoo_url" => "https://odoo.example.com",
          "odoo_db" => "provider_labs",
          "odoo_user" => "billing@example.com",
          "odoo_apikey" => "odoo-key-123"
        }
      )
      |> render_submit()

      assert has_element?(lv, "#company-step-3-form")

      {:ok, _lv, html} =
        lv
        |> form("#company-step-3-form",
          company: %{
            "provider_endpoint" => "https://sandbox.e-taxcore.com/api/v2/e-docs",
            "provider_apikey" => "provider-key-123"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/companies")

      assert html =~ "Provider Endpoint"
      assert html =~ "Configured"

      company =
        scope
        |> Accounts.list_companies()
        |> Enum.find(&(&1.company_name == "Stubbed Company SRL"))

      assert company.rnc == "132190068"
      assert company.company_name == "Stubbed Company SRL"
      assert company.economic_activity == "SOFTWARE SERVICES"
      assert company.local_administration == "ADM LOCAL CENTRAL"
      assert company.provider_endpoint == "https://sandbox.e-taxcore.com/api/v2/e-docs"
      assert company.provider_apikey == "provider-key-123"
    end

    test "blocks progression when the DGII lookup fails", %{conn: conn} do
      Application.put_env(
        :edoc,
        :company_onboarding_test_results,
        %{dgii_lookup_result: {:error, :result_not_found}}
      )

      {:ok, lv, _html} = live(conn, ~p"/companies/new")

      html =
        lv
        |> form("#company-step-1-form", company: %{"rnc" => "132190068"})
        |> render_submit()

      assert html =~ "DGII did not return a company for that RNC."
      assert has_element?(lv, "#company-step-1-form")
      refute has_element?(lv, "#company-step-2-form")
    end
  end

  describe "edit company" do
    test "updates provider settings while preserving blank secret inputs", %{
      conn: conn,
      scope: scope
    } do
      company =
        company_fixture(scope, %{
          company_name: "Edit Provider Co",
          provider_endpoint: "https://provider.example.com/original",
          provider_apikey: "original-provider-key",
          odoo_apikey: "original-odoo-key",
          access_token: "original-access-token"
        })

      {:ok, lv, _html} = live(conn, ~p"/companies/#{company.id}/edit")

      params = %{
        "company_name" => company.company_name,
        "rnc" => company.rnc,
        "provider_endpoint" => "https://provider.example.com/updated",
        "provider_apikey" => "",
        "odoo_url" => company.odoo_url,
        "odoo_db" => company.odoo_db,
        "odoo_user" => company.odoo_user,
        "odoo_apikey" => "",
        "access_token" => ""
      }

      {:ok, _lv, html} =
        lv
        |> form("#company-form", company: params)
        |> render_submit()
        |> follow_redirect(conn, ~p"/companies")

      assert html =~ "https://provider.example.com/updated"

      updated_company = Accounts.get_company_for_scope!(scope, company.id)

      assert updated_company.provider_endpoint == "https://provider.example.com/updated"
      assert updated_company.provider_apikey == "original-provider-key"
      assert updated_company.odoo_apikey == "original-odoo-key"
      assert updated_company.access_token == "original-access-token"
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:edoc, key)
  defp restore_env(key, value), do: Application.put_env(:edoc, key, value)
end
