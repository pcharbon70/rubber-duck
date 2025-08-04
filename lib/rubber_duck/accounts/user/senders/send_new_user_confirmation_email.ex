defmodule RubberDuck.Accounts.User.Senders.SendNewUserConfirmationEmail do
  @moduledoc """
  Sends an email for a new user to confirm their email address.
  """

  use AshAuthentication.Sender

  @impl true
  def send(_user, token, _) do
    IO.puts("""
    Click this link to confirm your email:

    /confirm_new_user/#{token}
    """)
  end
end
