defmodule EdocWeb.PageController do
  use EdocWeb, :controller

  alias EdocWeb.UserAuth

  def home(conn, _params) do
    case conn.assigns[:current_scope] do
      %{user: user} when not is_nil(user) ->
        redirect(conn, to: UserAuth.signed_in_path(conn))

      _ ->
        render(conn, :home, page_title: "Landing")
    end
  end
end
