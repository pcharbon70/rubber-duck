defmodule RubberDuckWeb.AuthController do
  @moduledoc """
  Authentication controller for handling sign in, sign out, and registration callbacks.
  """

  use RubberDuckWeb, :controller
  use AshAuthentication.Phoenix.Controller

  @doc """
  Successful authentication callback.
  Stores the user in session and redirects to the collaborative coding interface.
  """
  def success(conn, _activity, user, _token) do
    return_to = get_session(conn, :return_to) || ~p"/code"

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> assign(:current_user, user)
    |> put_flash(:info, "Welcome back, #{user.email}!")
    |> redirect(to: return_to)
  end

  @doc """
  Failed authentication callback.
  Shows an error message and redirects back to sign in.
  """
  def failure(conn, _activity, reason) do
    message =
      case reason do
        :invalid_credentials -> "Invalid email or password"
        :user_not_found -> "No account found with that email"
        :account_locked -> "Your account has been locked"
        _ -> "Authentication failed. Please try again."
      end

    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/sign-in")
  end

  @doc """
  Sign out action.
  Clears the session and redirects to the home page.
  """
  def sign_out(conn, _params) do
    return_to = get_session(conn, :return_to) || ~p"/"

    conn
    |> clear_session(:rubber_duck)
    |> put_flash(:info, "You have been signed out successfully.")
    |> redirect(to: return_to)
  end
end
