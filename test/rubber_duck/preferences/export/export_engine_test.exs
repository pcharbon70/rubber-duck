defmodule RubberDuck.Preferences.Export.ExportEngineTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Preferences.Export.ExportEngine
  alias RubberDuck.Preferences.Security.{AuditLogger, EncryptionManager}

  describe "export_preferences/1" do
    test "exports preferences in JSON format" do
      opts = [format: :json, scope: :system]

      with_mock RubberDuck.Preferences.Resources.SystemDefault, [:passthrough],
        read: fn -> {:ok, []} end do
        assert {:ok, result} = ExportEngine.export_preferences(opts)
        assert is_binary(result.data)
        assert result.metadata.format == :json
      end
    end

    test "exports preferences in YAML format" do
      opts = [format: :yaml, scope: :system]

      with_mock RubberDuck.Preferences.Resources.SystemDefault, [:passthrough],
        read: fn -> {:ok, []} end do
        assert {:ok, result} = ExportEngine.export_preferences(opts)
        assert is_binary(result.data)
        assert result.metadata.format == :yaml
      end
    end

    test "exports preferences in binary format" do
      opts = [format: :binary, scope: :system]

      with_mock RubberDuck.Preferences.Resources.SystemDefault, [:passthrough],
        read: fn -> {:ok, []} end do
        assert {:ok, result} = ExportEngine.export_preferences(opts)
        assert is_binary(result.data)
        assert result.metadata.format == :binary
      end
    end

    test "rejects unsupported export format" do
      opts = [format: :xml, scope: :system]

      assert {:error, "Unsupported export format: xml"} = ExportEngine.export_preferences(opts)
    end

    test "includes export metadata" do
      opts = [format: :json, scope: :all, include_metadata: true]

      with_mock RubberDuck.Preferences.Resources.SystemDefault, [:passthrough],
        read: fn -> {:ok, []} end do
        assert {:ok, result} = ExportEngine.export_preferences(opts)

        assert result.metadata.export_version
        assert result.metadata.exported_at
        assert result.metadata.format == :json
        assert result.metadata.scope == :all
      end
    end
  end

  describe "export_user_preferences/2" do
    test "exports user-specific preferences" do
      user_id = "user123"
      opts = [format: :json]

      with_mock RubberDuck.Preferences.Resources.UserPreference, [:passthrough],
        by_user: fn ^user_id -> {:ok, []} end do
        assert {:ok, result} = ExportEngine.export_user_preferences(user_id, opts)
        assert result.metadata.scope == :user
      end
    end
  end

  describe "export_system_defaults/1" do
    test "exports system defaults only" do
      opts = [format: :json]

      with_mock RubberDuck.Preferences.Resources.SystemDefault, [:passthrough],
        read: fn -> {:ok, []} end do
        assert {:ok, result} = ExportEngine.export_system_defaults(opts)
        assert result.metadata.scope == :system
      end
    end
  end

  describe "create_backup_export/1" do
    test "creates comprehensive backup with metadata" do
      opts = [format: :binary]

      with_mock RubberDuck.Preferences.Resources.SystemDefault, [:passthrough],
        read: fn -> {:ok, []} end do
        assert {:ok, result} = ExportEngine.create_backup_export(opts)

        assert result.backup_id
        assert result.metadata.scope == :all
        assert result.metadata.encryption_used == true
        assert result.metadata.compression_used == true
      end
    end

    test "logs backup creation" do
      opts = [format: :json]

      with_mock RubberDuck.Preferences.Resources.SystemDefault, [:passthrough],
        read: fn -> {:ok, []} end do
        with_mock RubberDuck.Preferences.Security.AuditLogger, [:passthrough],
          log_preference_change: fn _event -> :ok end do
          assert {:ok, _result} = ExportEngine.create_backup_export(opts)

          # Verify audit logging was called
          assert_called(AuditLogger.log_preference_change(_))
        end
      end
    end
  end

  describe "encryption handling" do
    test "encrypts sensitive preferences when enabled" do
      mock_defaults = [
        %{
          preference_key: "api.secret_key",
          default_value: "secret123",
          category: "api",
          description: "API secret key",
          data_type: "string",
          constraints: nil
        }
      ]

      opts = [format: :json, scope: :system, encrypt_sensitive: true]

      with_mock RubberDuck.Preferences.Resources.SystemDefault, [:passthrough],
        read: fn -> {:ok, mock_defaults} end do
        with_mock RubberDuck.Preferences.Security.EncryptionManager, [:passthrough],
          sensitive_preference?: fn "api.secret_key" -> true end,
          encrypt_if_sensitive: fn "api.secret_key", "secret123" -> {:ok, "encrypted_value"} end do
          assert {:ok, result} = ExportEngine.export_preferences(opts)

          # Verify encryption was applied
          assert_called(EncryptionManager.encrypt_if_sensitive(_, _))
        end
      end
    end

    test "does not encrypt when encryption is disabled" do
      opts = [format: :json, scope: :system, encrypt_sensitive: false]

      with_mock RubberDuck.Preferences.Resources.SystemDefault, [:passthrough],
        read: fn -> {:ok, []} end do
        assert {:ok, result} = ExportEngine.export_preferences(opts)
        assert result.metadata.encryption_used == false
      end
    end
  end
end
