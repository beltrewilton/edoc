defmodule EdocWeb.PageController do
  use EdocWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
