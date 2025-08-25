defmodule RubberDuck.Preferences.Migration.VersionManagerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Preferences.Migration.VersionManager

  describe "current_version/0" do
    test "returns current schema version" do
      # Mock the current version lookup
      with_mock RubberDuck.Preferences.Resources.PreferenceSchemaVersion, [:passthrough],
        current_version: fn -> {:ok, [%{version: "1.2.3"}]} end do
        assert {:ok, "1.2.3"} = VersionManager.current_version()
      end
    end

    test "returns default version when no current version exists" do
      with_mock RubberDuck.Preferences.Resources.PreferenceSchemaVersion, [:passthrough],
        current_version: fn -> {:ok, []} end do
        assert {:ok, "1.0.0"} = VersionManager.current_version()
      end
    end
  end

  describe "valid_version?/1" do
    test "validates correct semantic versions" do
      assert VersionManager.valid_version?("1.0.0")
      assert VersionManager.valid_version?("2.1.5")
      assert VersionManager.valid_version?("10.20.30")
      assert VersionManager.valid_version?("1.0.0-alpha")
      assert VersionManager.valid_version?("1.0.0-beta.1")
    end

    test "rejects invalid version formats" do
      refute VersionManager.valid_version?("1.0")
      refute VersionManager.valid_version?("v1.0.0")
      refute VersionManager.valid_version?("1.0.0.0")
      refute VersionManager.valid_version?("invalid")
      refute VersionManager.valid_version?("")
      refute VersionManager.valid_version?(nil)
      refute VersionManager.valid_version?(123)
    end
  end

  describe "migration_required?/1" do
    test "returns true when target version is newer" do
      with_mock RubberDuck.Preferences.Resources.PreferenceSchemaVersion, [:passthrough],
        current_version: fn -> {:ok, [%{version: "1.0.0"}]} end do
        assert {:ok, true} = VersionManager.migration_required?("1.1.0")
        assert {:ok, true} = VersionManager.migration_required?("2.0.0")
      end
    end

    test "returns false when target version is same or older" do
      with_mock RubberDuck.Preferences.Resources.PreferenceSchemaVersion, [:passthrough],
        current_version: fn -> {:ok, [%{version: "1.1.0"}]} end do
        assert {:ok, false} = VersionManager.migration_required?("1.1.0")
        assert {:ok, false} = VersionManager.migration_required?("1.0.0")
      end
    end
  end

  describe "versions_compatible?/2" do
    test "returns true for same versions" do
      assert VersionManager.versions_compatible?("1.0.0", "1.0.0")
    end

    test "returns true for compatible versions in same major" do
      assert VersionManager.versions_compatible?("1.0.0", "1.1.0")
      assert VersionManager.versions_compatible?("1.5.0", "1.2.0")
    end

    test "returns false for different major versions" do
      refute VersionManager.versions_compatible?("1.0.0", "2.0.0")
      refute VersionManager.versions_compatible?("2.1.0", "1.9.0")
    end
  end

  describe "register_version/1" do
    test "creates new schema version record" do
      version_params = %{
        version: "1.2.0",
        version_name: "Test Version",
        description: "Test schema version",
        migration_required: true,
        breaking_changes: false
      }

      with_mock RubberDuck.Preferences.Resources.PreferenceSchemaVersion, [:passthrough],
        create: fn _params -> {:ok, %{version: "1.2.0", id: "test-id"}} end do
        assert {:ok, result} = VersionManager.register_version(version_params)
        assert result.version == "1.2.0"
      end
    end

    test "handles creation errors" do
      with_mock RubberDuck.Preferences.Resources.PreferenceSchemaVersion, [:passthrough],
        create: fn _params -> {:error, "Database error"} end do
        assert {:error, "Database error"} = VersionManager.register_version(%{version: "1.0.0"})
      end
    end
  end

  describe "apply_version/1" do
    test "marks version as applied" do
      mock_version = %{id: "test-id", version: "1.1.0"}

      with_mock RubberDuck.Preferences.Resources.PreferenceSchemaVersion, [:passthrough],
        by_version: fn "1.1.0" -> {:ok, [mock_version]} end,
        mark_applied: fn _version -> {:ok, %{mock_version | applied_at: DateTime.utc_now()}} end do
        assert {:ok, result} = VersionManager.apply_version("1.1.0")
        assert result.applied_at
      end
    end

    test "handles missing version" do
      with_mock RubberDuck.Preferences.Resources.PreferenceSchemaVersion, [:passthrough],
        by_version: fn "9.9.9" -> {:ok, []} end do
        assert {:error, "Schema version not found: 9.9.9"} = VersionManager.apply_version("9.9.9")
      end
    end
  end

  describe "up_to_date?/0" do
    test "returns true when at latest version" do
      mock_latest = %{version: "1.5.0"}

      with_mock RubberDuck.Preferences.Resources.PreferenceSchemaVersion, [:passthrough],
        current_version: fn -> {:ok, [%{version: "1.5.0"}]} end,
        read: fn -> {:ok, [mock_latest]} end do
        assert {:ok, true} = VersionManager.up_to_date?()
      end
    end

    test "returns false when not at latest version" do
      mock_latest = %{version: "1.5.0"}

      with_mock RubberDuck.Preferences.Resources.PreferenceSchemaVersion, [:passthrough],
        current_version: fn -> {:ok, [%{version: "1.0.0"}]} end,
        read: fn -> {:ok, [mock_latest]} end do
        assert {:ok, false} = VersionManager.up_to_date?()
      end
    end
  end
end
