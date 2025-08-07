defmodule RubberDuck.Actions.Core.UpdateEntity.ValidatorTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Actions.Core.UpdateEntity.Validator
  
  describe "validate/2" do
    setup do
      entity = %{
        id: "test-123",
        type: :user,
        email: "user@example.com",
        username: "testuser",
        role: :member,
        created_at: DateTime.utc_now()
      }
      
      {:ok, entity: entity}
    end
    
    test "validates successful changes", %{entity: entity} do
      params = %{
        current_entity: entity,
        changes: %{username: "newusername", role: :admin}
      }
      
      assert {:ok, result} = Validator.validate(params, %{})
      assert result.changes == %{username: "newusername", role: :admin}
      assert result.change_count == 2
      assert result.validations.field_validation.valid
      assert result.validations.security_check.valid
    end
    
    test "rejects invalid fields", %{entity: entity} do
      params = %{
        current_entity: entity,
        changes: %{invalid_field: "value"}
      }
      
      assert {:error, result} = Validator.validate(params, %{})
      assert result.reason == :validation_failed
      assert :field_validation in result.failed_checks
      assert "invalid_field" in result.validations.field_validation.invalid_fields
    end
    
    test "allows new fields that are permitted", %{entity: entity} do
      params = %{
        current_entity: entity,
        changes: %{preferences: %{theme: "dark"}}
      }
      
      assert {:ok, result} = Validator.validate(params, %{})
      assert result.changes.preferences == %{theme: "dark"}
    end
    
    test "detects type mismatches", %{entity: entity} do
      params = %{
        current_entity: entity,
        changes: %{username: 123}  # Should be string
      }
      
      assert {:error, result} = Validator.validate(params, %{})
      assert :compatibility_check in result.failed_checks
      compatibility = result.validations.compatibility_check
      assert not compatibility.valid
      assert {:username, :type_mismatch, _} = hd(compatibility.issues)
    end
    
    test "flags sensitive field modifications", %{entity: entity} do
      params = %{
        current_entity: entity,
        changes: %{email: "newemail@example.com"}
      }
      
      assert {:error, result} = Validator.validate(params, %{})
      assert :security_check in result.failed_checks
      security = result.validations.security_check
      assert {:email, :sensitive_field_modification} in security.risks
    end
    
    test "validates with constraints", %{entity: entity} do
      params = %{
        current_entity: entity,
        changes: %{username: "ab"},  # Too short
        validation_config: %{
          constraints: %{
            username: %{min: 3}
          }
        }
      }
      
      assert {:error, result} = Validator.validate(params, %{})
      assert :constraint_validation in result.failed_checks
    end
  end
  
  describe "validate_field_changes/2" do
    test "validates existing fields" do
      entity = %{name: "test", age: 25, type: :user}
      changes = %{name: "new", age: 26}
      
      result = Validator.validate_field_changes(changes, entity)
      
      assert result.valid
      assert result.invalid_fields == []
      assert :name in result.validated_fields
      assert :age in result.validated_fields
    end
    
    test "rejects unknown fields" do
      entity = %{name: "test", type: :user}
      changes = %{unknown: "value"}
      
      result = Validator.validate_field_changes(changes, entity)
      
      assert not result.valid
      assert result.invalid_fields == [:unknown]
    end
    
    test "allows permitted new fields" do
      entity = %{name: "test", type: :user}
      changes = %{metadata: %{}}
      
      result = Validator.validate_field_changes(changes, entity)
      
      assert result.valid
      assert result.invalid_fields == []
    end
  end
  
  describe "validate_constraints/2" do
    test "validates min constraint" do
      changes = %{age: 17}
      config = %{constraints: %{age: %{min: 18}}}
      
      result = Validator.validate_constraints(changes, config)
      
      assert not result.valid
      assert {:age, %{min: 18}, 17} in result.violations
    end
    
    test "validates max constraint" do
      changes = %{score: 101}
      config = %{constraints: %{score: %{max: 100}}}
      
      result = Validator.validate_constraints(changes, config)
      
      assert not result.valid
      assert {:score, %{max: 100}, 101} in result.violations
    end
    
    test "validates pattern constraint" do
      changes = %{email: "invalid"}
      config = %{constraints: %{email: %{pattern: ~r/@/}}}
      
      result = Validator.validate_constraints(changes, config)
      
      assert not result.valid
    end
    
    test "passes valid constraints" do
      changes = %{age: 25, score: 85}
      config = %{
        constraints: %{
          age: %{min: 18, max: 100},
          score: %{min: 0, max: 100}
        }
      }
      
      result = Validator.validate_constraints(changes, config)
      
      assert result.valid
      assert result.violations == []
    end
  end
  
  describe "check_compatibility/2" do
    test "detects type mismatches" do
      entity = %{name: "test", age: 25}
      changes = %{name: 123, age: "not a number"}
      
      result = Validator.check_compatibility(changes, entity)
      
      assert not result.valid
      assert length(result.issues) == 2
      assert result.compatibility_score == 0.0
    end
    
    test "allows compatible type changes" do
      entity = %{name: "test", count: 10}
      changes = %{name: "updated", count: 20}
      
      result = Validator.check_compatibility(changes, entity)
      
      assert result.valid
      assert result.issues == []
      assert result.compatibility_score == 1.0
    end
  end
  
  describe "perform_security_validation/2" do
    test "flags sensitive field modifications for user" do
      changes = %{email: "new@example.com", permissions: [:admin]}
      
      result = Validator.perform_security_validation(changes, :user)
      
      assert not result.valid
      assert {:email, :sensitive_field_modification} in result.risks
      assert {:permissions, :sensitive_field_modification} in result.risks
      assert result.risk_level == :medium
    end
    
    test "detects potential sensitive data in values" do
      changes = %{config: "api_key=secret123"}
      
      result = Validator.perform_security_validation(changes, :project)
      
      assert not result.valid
      assert {:config, :potential_sensitive_data} in result.risks
    end
    
    test "passes non-sensitive changes" do
      changes = %{name: "New Name", description: "Updated"}
      
      result = Validator.perform_security_validation(changes, :project)
      
      assert result.valid
      assert result.risks == []
      assert result.risk_level == :none
    end
  end
  
  describe "sanitize_changes/1" do
    test "trims whitespace from strings" do
      changes = %{name: "  test  ", description: "\n\nhello\n\n"}
      
      result = Validator.sanitize_changes(changes)
      
      assert result.name == "test"
      assert result.description == "hello"
    end
    
    test "removes control characters" do
      changes = %{text: "hello\x00world\x1F"}
      
      result = Validator.sanitize_changes(changes)
      
      assert result.text == "helloworld"
    end
    
    test "sanitizes nested maps" do
      changes = %{
        config: %{
          name: "  test  ",
          value: "clean"
        }
      }
      
      result = Validator.sanitize_changes(changes)
      
      assert result.config.name == "test"
      assert result.config.value == "clean"
    end
    
    test "sanitizes lists" do
      changes = %{
        tags: ["  tag1  ", "tag2", "  tag3"]
      }
      
      result = Validator.sanitize_changes(changes)
      
      assert result.tags == ["tag1", "tag2", "tag3"]
    end
  end
  
  describe "assess_change_severity/2" do
    test "assesses critical changes" do
      entity = %{type: :user, email: "old@example.com", username: "user"}
      changes = %{email: "new@example.com"}
      
      severity = Validator.assess_change_severity(changes, entity)
      
      assert severity == :critical
    end
    
    test "assesses low severity changes" do
      entity = %{type: :user, username: "user", metadata: %{}}
      changes = %{metadata: %{theme: "dark"}}
      
      severity = Validator.assess_change_severity(changes, entity)
      
      assert severity == :low
    end
    
    test "handles empty changes" do
      entity = %{type: :user}
      changes = %{}
      
      severity = Validator.assess_change_severity(changes, entity)
      
      assert severity == :none
    end
  end
  
  describe "allowed_new_fields/1" do
    test "returns correct fields for user type" do
      fields = Validator.allowed_new_fields(:user)
      assert :preferences in fields
      assert :settings in fields
      assert :metadata in fields
    end
    
    test "returns correct fields for project type" do
      fields = Validator.allowed_new_fields(:project)
      assert :tags in fields
      assert :collaborators in fields
    end
    
    test "returns default fields for unknown type" do
      fields = Validator.allowed_new_fields(:unknown)
      assert fields == [:metadata]
    end
  end
end