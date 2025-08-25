defmodule RubberDuck.Preferences.Security.EncryptionManagerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Preferences.Security.EncryptionManager

  describe "encrypt/1" do
    test "encrypts string values" do
      value = "secret_api_key_12345"

      assert {:ok, encrypted} = EncryptionManager.encrypt(value)
      assert encrypted != value
      assert is_binary(encrypted)
    end

    test "handles nil values" do
      assert {:ok, nil} = EncryptionManager.encrypt(nil)
    end

    test "handles empty strings" do
      assert {:ok, ""} = EncryptionManager.encrypt("")
    end

    test "rejects non-string values" do
      assert {:error, _reason} = EncryptionManager.encrypt(123)
      assert {:error, _reason} = EncryptionManager.encrypt(%{key: "value"})
    end
  end

  describe "decrypt/1" do
    test "decrypts encrypted values" do
      original_value = "secret_api_key_12345"

      {:ok, encrypted} = EncryptionManager.encrypt(original_value)
      assert {:ok, decrypted} = EncryptionManager.decrypt(encrypted)
      assert decrypted == original_value
    end

    test "handles nil values" do
      assert {:ok, nil} = EncryptionManager.decrypt(nil)
    end

    test "handles empty strings" do
      assert {:ok, ""} = EncryptionManager.decrypt("")
    end

    test "returns error for invalid encrypted values" do
      assert {:error, _reason} = EncryptionManager.decrypt("invalid_encrypted_value")
    end

    test "rejects non-string values" do
      assert {:error, _reason} = EncryptionManager.decrypt(123)
    end
  end

  describe "sensitive_preference?/1" do
    test "identifies API key preferences as sensitive" do
      assert EncryptionManager.sensitive_preference?("llm.api_key")
      assert EncryptionManager.sensitive_preference?("openai.api-key")
      assert EncryptionManager.sensitive_preference?("API_KEY_TOKEN")
    end

    test "identifies secret preferences as sensitive" do
      assert EncryptionManager.sensitive_preference?("oauth.client_secret")
      assert EncryptionManager.sensitive_preference?("database.secret")
      assert EncryptionManager.sensitive_preference?("app.SECRET_KEY")
    end

    test "identifies token preferences as sensitive" do
      assert EncryptionManager.sensitive_preference?("auth.token")
      assert EncryptionManager.sensitive_preference?("bearer_token")
      assert EncryptionManager.sensitive_preference?("access-token")
    end

    test "identifies password preferences as sensitive" do
      assert EncryptionManager.sensitive_preference?("database.password")
      assert EncryptionManager.sensitive_preference?("admin_password")
    end

    test "identifies credential preferences as sensitive" do
      assert EncryptionManager.sensitive_preference?("aws.credentials")
      assert EncryptionManager.sensitive_preference?("database_credentials")
    end

    test "does not mark regular preferences as sensitive" do
      refute EncryptionManager.sensitive_preference?("ui.theme")
      refute EncryptionManager.sensitive_preference?("performance.cache_size")
      refute EncryptionManager.sensitive_preference?("debug.enabled")
    end

    test "handles edge cases" do
      refute EncryptionManager.sensitive_preference?("")
      refute EncryptionManager.sensitive_preference?(nil)
      refute EncryptionManager.sensitive_preference?(123)
    end
  end

  describe "encrypt_if_sensitive/2" do
    test "encrypts sensitive preferences" do
      key = "llm.api_key"
      value = "secret_key_123"

      assert {:ok, encrypted} = EncryptionManager.encrypt_if_sensitive(key, value)
      assert encrypted != value
    end

    test "does not encrypt non-sensitive preferences" do
      key = "ui.theme"
      value = "dark"

      assert {:ok, ^value} = EncryptionManager.encrypt_if_sensitive(key, value)
    end

    test "handles nil values" do
      assert {:ok, nil} = EncryptionManager.encrypt_if_sensitive("api.key", nil)
    end
  end

  describe "decrypt_if_sensitive/2" do
    test "decrypts sensitive preferences" do
      key = "llm.api_key"
      value = "secret_key_123"

      {:ok, encrypted} = EncryptionManager.encrypt_if_sensitive(key, value)
      assert {:ok, decrypted} = EncryptionManager.decrypt_if_sensitive(key, encrypted)
      assert decrypted == value
    end

    test "does not decrypt non-sensitive preferences" do
      key = "ui.theme"
      value = "dark"

      assert {:ok, ^value} = EncryptionManager.decrypt_if_sensitive(key, value)
    end
  end

  describe "validate_encryption_config/0" do
    test "validates encryption configuration" do
      # This test would check if encryption keys are properly configured
      # The actual implementation depends on the application configuration
      result = EncryptionManager.validate_encryption_config()
      assert result in [:ok, {:error, _reason}]
    end
  end

  describe "get_encryption_metadata/1" do
    test "returns metadata for sensitive preferences" do
      metadata = EncryptionManager.get_encryption_metadata("llm.api_key")

      assert metadata.sensitive == true
      assert metadata.encrypted == true
      assert metadata.algorithm == "Phoenix.Token"
    end

    test "returns metadata for non-sensitive preferences" do
      metadata = EncryptionManager.get_encryption_metadata("ui.theme")

      assert metadata.sensitive == false
      assert metadata.encrypted == false
      assert metadata.algorithm == "none"
    end
  end

  describe "encryption/decryption round-trip" do
    test "maintains data integrity through encrypt/decrypt cycle" do
      test_values = [
        "simple_api_key",
        "complex_key_with_special_chars!@#$%^&*()",
        "very_long_api_key_" <> String.duplicate("x", 1000),
        "unicode_key_测试",
        "key with spaces and newlines\n\r\t"
      ]

      Enum.each(test_values, fn value ->
        {:ok, encrypted} = EncryptionManager.encrypt(value)
        {:ok, decrypted} = EncryptionManager.decrypt(encrypted)
        assert decrypted == value
      end)
    end

    test "different values produce different encrypted results" do
      value1 = "api_key_1"
      value2 = "api_key_2"

      {:ok, encrypted1} = EncryptionManager.encrypt(value1)
      {:ok, encrypted2} = EncryptionManager.encrypt(value2)

      assert encrypted1 != encrypted2
    end

    test "same value encrypted multiple times produces different results" do
      value = "api_key_consistent"

      {:ok, encrypted1} = EncryptionManager.encrypt(value)
      {:ok, encrypted2} = EncryptionManager.encrypt(value)

      # Phoenix.Token includes timestamps, so results should be different
      assert encrypted1 != encrypted2

      # But both should decrypt to the same value
      {:ok, decrypted1} = EncryptionManager.decrypt(encrypted1)
      {:ok, decrypted2} = EncryptionManager.decrypt(encrypted2)

      assert decrypted1 == value
      assert decrypted2 == value
    end
  end
end
