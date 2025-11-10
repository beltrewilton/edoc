defmodule Edoc.TenantContext do
  def put_tenant(tenant), do: Process.put(:current_tenant, tenant)
  def get_tenant(), do: Process.get(:current_tenant, "Not.Found.In.TenantContext")
end
