defmodule EdocWeb.WebhookControllerTest do
  use EdocWeb.ConnCase, async: true

  import Edoc.AccountsFixtures

  alias Edoc.{Accounts, Repo, TenantContext, Transaction}
  alias Ecto.Adapters.SQL.Sandbox
  alias Triplex

  describe "POST /:user_id/:company_id" do
    setup %{conn: conn} do
      tenant = tenant_fixture()

      on_exit(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Triplex.drop(tenant, Repo)
        end)
      end)

      {:ok, conn: put_req_header(conn, "content-type", "application/json"), tenant: tenant}
    end

    test "returns 401 when user or company cannot be resolved", %{conn: conn} do
      path = ~p"/#{Ecto.UUID.generate()}/#{Ecto.UUID.generate()}"
      conn = post(conn, path, Jason.encode!(%{"payload" => %{}}))

      assert %{"error" => "unauthorized"} = json_response(conn, 401)
    end

    test "persists a transaction for the tenant company", %{conn: conn, tenant: tenant} do
      user = user_fixture()
      {:ok, user} = Accounts.update_user_tenant(user, %{tenant: tenant})

      TenantContext.put_tenant(tenant)
      scope = user_scope_fixture(user)
      company = company_fixture(scope)

      payload = %{"_id" => "abc123", "foo" => "bar"}

      conn = post(conn, ~p"/#{user.id}/#{company.id}", Jason.encode!(payload))

      assert %{"status" => "accepted"} = json_response(conn, 201)

      [tx] = Repo.all(Transaction, prefix: tenant)
      assert tx.company_id == company.id
      assert tx.odoo_request == payload
      assert tx.odoo_request_at
    end
  end
end
