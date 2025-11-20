defmodule EdocWeb.GoogleAuthController do
  use EdocWeb, :controller

  alias Edoc.Accounts
  alias EdocWeb.UserAuth

  def redirect_to(conn, _params) do
    redirect(conn, external: EdocWeb.GoogleLiveHelper.google_auth_url())
  end

  # Google OAuth2 callback: exchange code, fetch userinfo, persist, and log in
  def callback(conn, %{"code" => code}) do
    with {:ok, token_map} <- exchange_code_for_token(code),
         {:ok, user_info} <- fetch_user_info(token_map["access_token"]),
         {:ok, {%Accounts.User{} = user, _}} <-
           normalize_upsert_result(Accounts.upsert_user_from_google(user_info, token_map)) do
      conn
      |> put_flash(:info, "Logged in with Google")
      |> UserAuth.log_in_user(user, %{})
    else
      {:error, reason} ->
        conn
        |> put_flash(:error, "Google sign-in failed: #{inspect(reason)}")
        |> redirect(to: ~p"/users/log-in")

      _ ->
        conn
        |> put_flash(:error, "Google sign-in failed.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  defp normalize_upsert_result({:ok, %Accounts.User{} = user}), do: {:ok, {user, nil}}

  defp normalize_upsert_result({:ok, {user, _} = tuple}) when is_struct(user, Accounts.User),
    do: {:ok, tuple}

  defp normalize_upsert_result(other), do: other

  defp exchange_code_for_token(code) do
    redirect_uri = google_redirect_uri()

    form = %{
      "client_id" => System.fetch_env!("GOOGLE_CLIENT"),
      "client_secret" => System.fetch_env!("GOOGLE_KEY"),
      "code" => code,
      "redirect_uri" => redirect_uri,
      "grant_type" => "authorization_code"
    }

    case Req.post("https://oauth2.googleapis.com/token", form: form) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_user_info(access_token) do
    headers = [{"Authorization", "Bearer #{access_token}"}]

    case Req.get("https://www.googleapis.com/oauth2/v3/userinfo", headers: headers) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp google_redirect_uri do
    "https://a0c15d085bf1.ngrok-free.app/auth/google/callback"
  end
end
