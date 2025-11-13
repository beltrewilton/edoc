defmodule EdocWeb.Plugs.PutTenantFromScope do
  @moduledoc """
  Sets the tenant in the process dictionary from the current scope.

  This should run after `fetch_current_scope_for_user` so `conn.assigns.current_scope`
  is available. Useful for controller requests; LiveViews should also ensure
  they set the tenant in their mount callbacks since they run in a different process.
  """
  import Plug.Conn
  alias Edoc.TenantContext

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_in(conn.assigns, [:current_scope, Access.key(:user), Access.key(:tenant)]) do
      tenant when is_binary(tenant) and tenant != "" -> TenantContext.put_tenant(tenant)
      _ -> :ok
    end

    conn
  end
end
