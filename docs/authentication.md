# Authentication System Documentation

## Overview

RubberDuck uses a **simple username and password authentication system**. No email addresses are collected or required. This privacy-first approach ensures users can maintain complete anonymity while using the system.

## Key Features

- **Authentication Method**: Username and password only
- **No Email Required**: Complete privacy - no email addresses collected
- **JWT Token-based Sessions**: Secure token generation and validation
- **Password Security**: bcrypt hashing with configurable rounds
- **No Password Reset**: Admin intervention required for password resets

## User Resource Structure

### Fields
- `username`: Unique username (case-insensitive)
- `password`: Minimum 8 characters (hashed with bcrypt)
- `id`: UUID primary key (auto-generated)
- `hashed_password`: bcrypt hash of the password (internal)

## Authentication Actions

### Registration
```elixir
# Register a new user
RubberDuck.Accounts.register_with_password(%{
  username: "johndoe",
  password: "securepass123",
  password_confirmation: "securepass123"
})
```

### Sign In
```elixir
# Sign in with username and password
RubberDuck.Accounts.sign_in_with_password(%{
  username: "johndoe",
  password: "securepass123"
})
```

### Password Change
```elixir
# Users can change their password if they know their current password
RubberDuck.Accounts.change_password(user, %{
  current_password: "oldpassword",
  password: "newpassword",
  password_confirmation: "newpassword"
})
```

### Password Reset
Password reset is not available through self-service. Users who forget their password must contact an administrator for manual password reset.

## Security Considerations

1. **Unique Constraints**:
   - Username must be globally unique
   - No duplicate usernames allowed

2. **Case Sensitivity**:
   - Username uses case-insensitive strings (`:ci_string`)
   - "JohnDoe" and "johndoe" are treated as the same username

3. **Token Security**:
   - JWT tokens with configurable expiration
   - Token storage and validation through `RubberDuck.Accounts.Token`
   - Signing secrets managed by `RubberDuck.Secrets`

4. **Password Requirements**:
   - Minimum 8 characters
   - Stored using bcrypt hashing
   - Password confirmation required for registration and reset

## Database Schema

The users table structure:
```sql
CREATE TABLE users (
  id UUID PRIMARY KEY,
  username CITEXT NOT NULL,
  hashed_password TEXT NOT NULL,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE UNIQUE INDEX users_unique_username_index ON users(username);
```

## Configuration

### Ash Authentication Configuration
```elixir
authentication do
  strategies do
    password :password do
      identity_field :username
      hash_provider AshAuthentication.BcryptProvider
      # Password reset disabled - admin handles resets
    end
  end
end
```

### Identity Configuration
```elixir
identities do
  identity :unique_username, [:username]
end
```

## Testing Considerations

When testing authentication:
- Test username registration and validation
- Verify duplicate username rejection
- Test case-insensitive username matching
- Verify password change functionality
- Test JWT token generation and validation
- Ensure proper password hashing with bcrypt

## Admin Operations

### Manual Password Reset
Administrators can manually reset a user's password through the console:

```elixir
# Find the user
user = RubberDuck.Accounts.get_by_username!("johndoe")

# Update their password directly (bypassing current password check)
RubberDuck.Accounts.update!(user, %{
  hashed_password: Bcrypt.hash_pwd_salt("new_temporary_password")
})
```

## Future Enhancements

Potential improvements to consider:
- Two-factor authentication (2FA) using TOTP
- Security questions for account recovery
- Username change functionality with history
- Session management and device tracking
- Login attempt monitoring and lockout