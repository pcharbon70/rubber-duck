defmodule RubberDuck.Secrets do
  @moduledoc """
  Handles secret resolution for AshAuthentication.

  This module provides secrets for authentication tokens and signing keys.
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
