defmodule RubberDuck.Secrets do
  @moduledoc """
  Secret management module for RubberDuck authentication.
  
  Provides JWT token signing secrets and handles secret rotation
  for secure authentication token management.
  """

  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        RubberDuck.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:rubber_duck, :token_signing_secret)
  end
end
