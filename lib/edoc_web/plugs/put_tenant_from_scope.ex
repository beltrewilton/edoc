defmodule EdocWeb.Plugs.PutTenantFromScope do
  @moduledoc """
  Sets the tenant in the process dictionary from the current scope.

  This should run after `fetch_current_scope_for_user` so `conn.assigns.current_scope`
  is available. Useful for controller requests; LiveViews should also ensure
  they set the tenant in their mount callbacks since they run in a different process.
  """
  import Plug.Conn
  alias Edoc.TenantContext
  @invalid_tenant_prefix "Not.Found.In.TenantContext"

  def init(opts), do: opts

  def call(conn, _opts) do
    tenant = get_in(conn.assigns, [:current_scope, Access.key(:user), Access.key(:tenant)])

    if valid_tenant?(tenant) do
      TenantContext.put_tenant(tenant)
    end

    conn
  end

  defp valid_tenant?(tenant) when is_binary(tenant) do
    tenant != "" and not String.starts_with?(tenant, @invalid_tenant_prefix)
  end

  defp valid_tenant?(_), do: false
end
