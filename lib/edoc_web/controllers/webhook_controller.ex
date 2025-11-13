defmodule EdocWeb.WebhookController do
  use EdocWeb, :controller

  alias Edoc.Accounts.{Company, User}
  alias Edoc.Transaction
  alias Edoc.Repo

  @body_opts [length: 10_000_000, read_timeout: 15_000]

  def create(conn, %{"user_id" => user_id, "company_id" => company_id}) do
    with {:ok, payload} <- decode_body(conn),
         {:ok, user} <- fetch_user(user_id),
         {:ok, tenant} <- tenant_for_user(user),
         {:ok, company} <- fetch_company(company_id, tenant),
         {:ok, _record} <- insert_transaction(company, tenant, payload) do
      conn
      |> put_status(:created)
      |> json(%{status: "accepted"})
    else
      {:error, :invalid_payload} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid payload"})

      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "unable to store transaction", details: errors_on(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "failed to store transaction", reason: inspect(reason)})
    end
  end

  defp decode_body(conn) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} ->
        with {:ok, raw, _conn} <- Plug.Conn.read_body(conn, @body_opts),
             {:ok, decoded} <- Jason.decode(raw),
             true <- is_map(decoded) do
          {:ok, decoded}
        else
          _ -> {:error, :invalid_payload}
        end

      %{} = params ->
        {:ok, params}
    end
  end

  defp fetch_user(user_id) do
    case Repo.get(User, user_id) do
      %User{} = user -> {:ok, user}
      _ -> {:error, :unauthorized}
    end
  end

  defp tenant_for_user(%User{tenant: tenant}) when is_binary(tenant) and byte_size(tenant) > 0 do
    {:ok, tenant}
  end

  defp tenant_for_user(_), do: {:error, :unauthorized}

  defp fetch_company(company_id, tenant) do
    case Repo.get(Company, company_id, prefix: tenant) do
      %Company{} = company -> {:ok, company}
      _ -> {:error, :unauthorized}
    end
  end

  defp insert_transaction(%Company{id: company_id}, tenant, payload) do
    attrs = %{
      company_id: company_id,
      odoo_request: payload,
      odoo_request_at: DateTime.utc_now(:second)
    }

    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Repo.insert(prefix: tenant)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
