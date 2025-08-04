defmodule RubberDuck.Accounts do
  use Ash.Domain,
    otp_app: :rubber_duck

  resources do
    resource RubberDuck.Accounts.Token
    
    resource RubberDuck.Accounts.User do
      define :register_user, action: :register_with_password
      define :sign_in_user, action: :sign_in_with_password
      define :get_user, action: :read, get_by: [:id]
      define :get_user_by_username, action: :get_by_username, args: [:username]
      define :change_user_password, action: :change_password
    end
  end
end
