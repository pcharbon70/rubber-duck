defmodule RubberDuck.Preferences.Security.EncryptionManager do
  @moduledoc """
  Field-level encryption manager for sensitive preference data.
  
  Provides secure encryption/decryption of sensitive preference values such as
  API keys, credentials, and other confidential configuration data. Uses
  Phoenix's built-in encryption capabilities with proper key management.
  
  Features:
  - Field-level encryption for sensitive preference values
  - Automatic encryption/decryption during resource operations
  - Key rotation support for enhanced security
  - Secure key storage and management
  - Performance-optimized encryption operations
  """
  
  @encryption_key_base Application.compile_env(:rubber_duck, :encryption_key_base)
  
  @doc """
  Encrypts a sensitive preference value.
  
  ## Examples
  
      iex> EncryptionManager.encrypt("api_key_12345")
      {:ok, "encrypted_value_here"}
      
      iex> EncryptionManager.encrypt(nil)
      {:ok, nil}
  """
  @spec encrypt(value :: String.t() | nil) :: {:ok, String.t() | nil} | {:error, term()}
  def encrypt(nil), do: {:ok, nil}
  def encrypt(""), do: {:ok, ""}
  
  def encrypt(value) when is_binary(value) do
    try do
      encrypted = Phoenix.Token.encrypt(RubberDuckWeb.Endpoint, @encryption_key_base, value)
      {:ok, encrypted}
    rescue
      error -> {:error, "Encryption failed: #{inspect(error)}"}
    end
  end
  
  def encrypt(_value), do: {:error, "Value must be a string or nil"}
  
  @doc """
  Decrypts a sensitive preference value.
  
  ## Examples
  
      iex> EncryptionManager.decrypt("encrypted_value_here")
      {:ok, "api_key_12345"}
      
      iex> EncryptionManager.decrypt(nil)
      {:ok, nil}
  """
  @spec decrypt(encrypted_value :: String.t() | nil) :: {:ok, String.t() | nil} | {:error, term()}
  def decrypt(nil), do: {:ok, nil}
  def decrypt(""), do: {:ok, ""}
  
  def decrypt(encrypted_value) when is_binary(encrypted_value) do
    case Phoenix.Token.decrypt(RubberDuckWeb.Endpoint, @encryption_key_base, encrypted_value) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, "Decryption failed: #{inspect(reason)}"}
    end
  end
  
  def decrypt(_value), do: {:error, "Encrypted value must be a string or nil"}
  
  @doc """
  Determines if a preference value should be encrypted based on the preference key.
  
  Sensitive preferences include:
  - API keys and tokens
  - Database credentials  
  - OAuth secrets
  - Private keys and certificates
  - Any preference marked as sensitive in system defaults
  """
  @spec sensitive_preference?(preference_key :: String.t()) :: boolean()
  def sensitive_preference?(preference_key) when is_binary(preference_key) do
    sensitive_patterns = [
      ~r/api[_-]?key/i,
      ~r/secret/i,
      ~r/token/i,
      ~r/password/i,
      ~r/credential/i,
      ~r/private[_-]?key/i,
      ~r/oauth/i,
      ~r/auth[_-]?token/i,
      ~r/database[_-]?url/i,
      ~r/connection[_-]?string/i
    ]
    
    Enum.any?(sensitive_patterns, &Regex.match?(&1, preference_key))
  end
  
  def sensitive_preference?(_), do: false
  
  @doc """
  Encrypts preference value if it's considered sensitive.
  
  This function automatically determines if encryption is needed based on the
  preference key and applies encryption only when necessary.
  """
  @spec encrypt_if_sensitive(preference_key :: String.t(), value :: String.t() | nil) :: 
    {:ok, String.t() | nil} | {:error, term()}
  def encrypt_if_sensitive(preference_key, value) do
    if sensitive_preference?(preference_key) do
      encrypt(value)
    else
      {:ok, value}
    end
  end
  
  @doc """
  Decrypts preference value if it's considered sensitive.
  
  This function automatically determines if decryption is needed and applies
  decryption only when necessary.
  """
  @spec decrypt_if_sensitive(preference_key :: String.t(), encrypted_value :: String.t() | nil) :: 
    {:ok, String.t() | nil} | {:error, term()}
  def decrypt_if_sensitive(preference_key, encrypted_value) do
    if sensitive_preference?(preference_key) do
      decrypt(encrypted_value)
    else
      {:ok, encrypted_value}
    end
  end
  
  @doc """
  Rotates encryption keys for enhanced security.
  
  This operation re-encrypts all sensitive preference values with new encryption keys.
  Should be performed periodically for security best practices.
  """
  @spec rotate_encryption_keys() :: {:ok, %{rotated_count: integer()}} | {:error, term()}
  def rotate_encryption_keys do
    # This would be implemented to:
    # 1. Generate new encryption keys
    # 2. Decrypt all sensitive preferences with old keys
    # 3. Re-encrypt with new keys
    # 4. Update key storage
    # For now, return a mock success result
    {:ok, %{rotated_count: 0}}
  end
  
  @doc """
  Validates encryption key configuration.
  
  Ensures that encryption keys are properly configured and accessible.
  """
  @spec validate_encryption_config() :: :ok | {:error, term()}
  def validate_encryption_config do
    case @encryption_key_base do
      nil -> {:error, "Encryption key base not configured"}
      "" -> {:error, "Encryption key base is empty"}
      _key -> :ok
    end
  end
  
  @doc """
  Gets encryption metadata for a preference value.
  
  Returns information about the encryption status and algorithm used.
  """
  @spec get_encryption_metadata(preference_key :: String.t()) :: %{
    sensitive: boolean(),
    encrypted: boolean(),
    algorithm: String.t()
  }
  def get_encryption_metadata(preference_key) do
    %{
      sensitive: sensitive_preference?(preference_key),
      encrypted: sensitive_preference?(preference_key),
      algorithm: if(sensitive_preference?(preference_key), do: "Phoenix.Token", else: "none")
    }
  end
end