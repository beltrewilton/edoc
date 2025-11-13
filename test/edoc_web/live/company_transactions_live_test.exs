defmodule EdocWeb.CompanyTransactionsLiveTest do
  use EdocWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Edoc.AccountsFixtures

  alias Edoc.Accounts
  alias Edoc.Accounts.Scope
  alias Edoc.TenantContext
  alias Ecto.Adapters.SQL.Sandbox
  alias Triplex

  describe "transactions feed" do
    setup [:register_and_log_in_user]

    setup %{user: user} do
      tenant = tenant_fixture()

      {:ok, user} = Accounts.update_user_tenant(user, %{tenant: tenant})
      scope = Scope.for_user(user)

      TenantContext.put_tenant(tenant)

      company =
        company_fixture(scope, %{
          company_name: "DGII Labs",
          rnc: "401004001"
        })

      first_tx =
        transaction_fixture(company, %{
          rnc: "401004001",
          e_doc: "DGII-42",
          amount: 2500.45,
          tax: 450.11
        })

      _second_tx =
        transaction_fixture(company, %{
          rnc: "131941968",
          e_doc: "DGII-43",
          amount: "180.00",
          tax: "36.00"
        })

      on_exit(fn ->
        Sandbox.unboxed_run(Edoc.Repo, fn ->
          Triplex.drop(tenant, Edoc.Repo)
        end)
      end)

      {:ok, %{company: company, tenant: tenant, primary_tx: first_tx, scope: scope}}
    end

    test "renders odoo payload fields", %{conn: conn, company: company, primary_tx: tx} do
      {:ok, lv, _html} = live(conn, ~p"/companies/#{company.id}/transactions")

      rnc = Map.get(tx.odoo_request, "rnc")

      assert has_element?(
               lv,
               "#transactions [data-role=\"transaction-row\"][data-rnc=\"#{rnc}\"]"
             )

      amount_html =
        lv
        |> element(
          "#transactions [data-role=\"transaction-row\"][data-rnc=\"#{rnc}\"] span[data-field=\"amount\"]"
        )
        |> render()

      assert amount_html =~ "RD$ 2500.45"

      tax_html =
        lv
        |> element(
          "#transactions [data-role=\"transaction-row\"][data-rnc=\"#{rnc}\"] span[data-field=\"tax\"]"
        )
        |> render()

      assert tax_html =~ "RD$ 450.11"

      payload_html =
        lv
        |> element("#transactions [data-role=\"transaction-row\"][data-rnc=\"#{rnc}\"] pre")
        |> render()

      assert payload_html =~ "\"e_doc\": \"DGII-42\""
    end
  end
end
