defmodule RubberDuckWeb.PageController do
  use RubberDuckWeb, :controller

  def home(conn, _params) do
    render(conn, :home, layout: false)
  end

  def demo_login(conn, _params) do
    conn
    |> put_session(:demo_user, %{
      id: "demo-#{System.unique_integer([:positive])}",
      username: "Demo User",
      email: "demo@rubberduck.ai"
    })
    |> put_flash(:info, "Welcome, Demo User! You're now in demo mode.")
    |> redirect(to: ~p"/code")
  end

  def demo_logout(conn, _params) do
    conn
    |> delete_session(:demo_user)
    |> put_flash(:info, "Demo session ended. Thanks for trying RubberDuck!")
    |> redirect(to: ~p"/")
  end
end