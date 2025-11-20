defmodule EdocWeb.GoogleLiveHelper do
  use EdocWeb, :live_view

  def doc, do: "Google login and callback handler for Edoc."

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, status: :idle, greeting: nil, messages_pair: [], google_account: nil)}
  end

  @impl true
  def handle_params(%{"code" => code} = _params, _uri, socket) do
    IO.inspect(code, label: "OAuth code received from Google")

    # Async task to avoid blocking LiveView mount
    send(self(), {:exchange_token, code})

    {:noreply, assign(socket, code: code, status: :exchanging)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, status: :idle)}
  end

  @impl true
  def handle_info({:exchange_token, code}, socket) do
    case exchange_code_for_token(code) do
      {:ok, token} ->
        IO.inspect(token, label: "Google token success")

        case fetch_user_info(token["access_token"]) do
          {:ok, google_account} ->
            IO.inspect(google_account, label: "Google User Info")
            _ = Edoc.Accounts.upsert_user_from_google(google_account, token)

            {:noreply,
             assign(socket,
               status: :success,
               google_account: google_account
             )}

          {:error, reason} ->
            {:noreply, assign(socket, status: :error, error: reason)}
        end

      {:error, reason} ->
        IO.inspect(reason, label: "Google token failed")
        {:noreply, assign(socket, status: :error, error: reason)}
    end
  end

  defp exchange_code_for_token(code) do
    form = %{
      "client_id" => System.fetch_env!("GOOGLE_CLIENT"),
      "client_secret" => System.fetch_env!("GOOGLE_KEY"),
      "code" => code,
      "redirect_uri" => google_redirect_uri(),
      "grant_type" => "authorization_code"
    }

    case Req.post("https://oauth2.googleapis.com/token", form: form) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  def google_auth_url do
    client_id = System.fetch_env!("GOOGLE_CLIENT")
    redirect_uri = URI.encode(google_redirect_uri())

    scope =
      URI.encode(
        "https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile"
      )

    "https://accounts.google.com/o/oauth2/auth" <>
      "?client_id=#{client_id}" <>
      "&redirect_uri=#{redirect_uri}" <>
      "&response_type=code" <>
      "&scope=#{scope}" <>
      "&access_type=offline" <>
      "&prompt=consent"
  end

  defp fetch_user_info(access_token) do
    IO.inspect(access_token, label: "Access Token for User Info")

    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Accept", "application/json"}
    ]

    case Req.get("https://www.googleapis.com/oauth2/v3/userinfo", headers: headers) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp google_redirect_uri do
    "https://a0c15d085bf1.ngrok-free.app/auth/google/callback"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div :if={@google_account} class="flex w-full col-2 gap-1 pl-1 pb-4">
        <.avatar online>
          <div class="w-12 rounded-full">
            <img src={@google_account["picture"]} />
          </div>
        </.avatar>
        <span class="w-full text-xl pl-3">
          {@google_account["name"]}
        </span>
      </div>

      <div class="p-4">
        <%= case @status do %>
          <% :idle -> %>
            <div>
              <h2 class="text-xl font-semibold mb-2">Connect Your Google Account</h2>
              <a
                href={google_auth_url()}
                class="bg-blue-500 hover:bg-blue-600 text-white font-bold py-2 px-4 rounded"
              >
                Connect with Google
              </a>
            </div>
          <% :exchanging -> %>
            <div>Exchanging code for token...</div>
          <% :success -> %>
            <div class="text-green-600">✅ Successfully connected with Google!</div>
          <% :error -> %>
            <div class="text-red-600">❌ Error: {inspect(@error)}</div>
          <% _ -> %>
            <div>Unknown state.</div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
