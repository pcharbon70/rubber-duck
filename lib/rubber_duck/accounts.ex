defmodule RubberDuck.Accounts do
  @moduledoc """
  Accounts domain for RubberDuck.

  Contains resources for user management, authentication tokens, and API keys.
  Provides admin interface through AshAdmin.
  """
  use Ash.Domain, otp_app: :rubber_duck, extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource RubberDuck.Accounts.Token
    resource RubberDuck.Accounts.User
    resource RubberDuck.Accounts.ApiKey
  end
end
