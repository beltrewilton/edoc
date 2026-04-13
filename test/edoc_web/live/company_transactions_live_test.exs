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
          odoo_request: %{
            "id" => 11287,
            "partner_vat" => "401004001",
            "invoice_partner_display_name" => "Santo Domingo Motors Company",
            "display_name" => "INV/2026/02/0008"
          },
          e_doc: "DGII-42",
          amount: 2500.45,
          tax: 450.11,
          odoo_request_at: ~U[2026-02-14 19:45:00Z],
          provider_request: %{"provider_marker" => "etaxcore"},
          provider_response: %{"status" => "accepted", "track_id" => "abc-123"}
        })

      _second_tx =
        transaction_fixture(company, %{
          odoo_request: %{
            "partner_vat" => "131941968",
            "invoice_partner_display_name" => "Cliente Fiscal",
            "display_name" => "INV/2026/02/0009"
          },
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

      rnc = Map.get(tx.odoo_request, "partner_vat")

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
      assert render(lv) =~ "SANTO DOMINGO MOTORS COMPANY"
      assert render(lv) =~ "DGII-42"
      assert render(lv) =~ "INV/2026/02/0008"
      assert render(lv) =~ "Feb 14, 2026"
      assert render(lv) =~ "03:45 PM"

      assert has_element?(
               lv,
               "#transactions a[href=\"#{company.odoo_url}/odoo/accounting/1/invoicing/11287\"]"
             )

      tax_html =
        lv
        |> element(
          "#transactions [data-role=\"transaction-row\"][data-rnc=\"#{rnc}\"] span[data-field=\"tax\"]"
        )
        |> render()

      assert tax_html =~ "RD$ 450.11"

      lv
      |> element("#raw-json-btn-#{tx.id}")
      |> render_click()

      modal_html =
        lv
        |> element("#transaction-raw-json-client")
        |> render()

      assert modal_html =~ "&quot;e_doc&quot;: &quot;DGII-42&quot;"
      assert render(lv) =~ "e-DOC: —"
      refute render(lv) =~ "Inserted at:"

      lv
      |> element("#raw-json-tab-provider")
      |> render_click()

      provider_modal_html =
        lv
        |> element("#transaction-raw-json-client")
        |> render()

      assert provider_modal_html =~ "&quot;provider_marker&quot;: &quot;etaxcore&quot;"

      lv
      |> element("#raw-json-tab-provider-response")
      |> render_click()

      provider_response_modal_html =
        lv
        |> element("#transaction-raw-json-client")
        |> render()

      assert provider_response_modal_html =~ "&quot;status&quot;: &quot;accepted&quot;"
      assert provider_response_modal_html =~ "&quot;track_id&quot;: &quot;abc-123&quot;"
    end

    test "uses rncEmisor in RNC column for E43", %{conn: conn, company: company} do
      transaction_fixture(company, %{
        odoo_request: %{
          "id" => 22334,
          "rncEmisor" => "101010101",
          "partner_vat" => "909090909",
          "invoice_partner_display_name" => "Proveedor Local",
          "display_name" => "BILL/2026/02/0010"
        },
        e_doc: "E43",
        amount: 1500.0,
        tax: 270.0
      })

      {:ok, lv, _html} = live(conn, ~p"/companies/#{company.id}/transactions")

      assert has_element?(
               lv,
               "#transactions [data-role=\"transaction-row\"][data-rnc=\"101010101\"]"
             )

      assert has_element?(
               lv,
               "#transactions a[href=\"#{company.odoo_url}/odoo/accounting/1/bills/22334\"]"
             )

      refute has_element?(
               lv,
               "#transactions [data-role=\"transaction-row\"][data-rnc=\"909090909\"]"
             )
    end
  end
end
