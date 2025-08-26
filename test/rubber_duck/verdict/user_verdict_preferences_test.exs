defmodule RubberDuck.Verdict.UserVerdictPreferencesTest do
  @moduledoc """
  Tests for UserVerdictPreferences resource.
  """
  
  use ExUnit.Case, async: true
  use RubberDuck.DataCase
  
  alias RubberDuck.Verdict.UserVerdictPreferences
  alias RubberDuck.Accounts.User
  
  setup do
    {:ok, user} = User.create(%{
      email: "test@example.com",
      first_name: "Test",
      last_name: "User"
    })
    
    %{user: user}
  end
  
  describe "user preferences creation" do
    test "create/1 creates user preferences with valid attributes", %{user: user} do
      attrs = %{
        user_id: user.id,
        quality_vs_cost_preference: Decimal.new("0.8"),
        evaluation_detail_level: :comprehensive,
        auto_accept_threshold: Decimal.new("0.95"),
        manual_review_threshold: Decimal.new("0.5"),
        personal_daily_budget: Decimal.new("75.00"),
        preferred_providers: ["anthropic", "openai"],
        security_emphasis: :high,
        learning_opt_in: true,
        feedback_frequency: :weekly
      }
      
      assert {:ok, preferences} = UserVerdictPreferences.create(attrs)
      
      assert preferences.user_id == user.id
      assert Decimal.equal?(preferences.quality_vs_cost_preference, Decimal.new("0.8"))
      assert preferences.evaluation_detail_level == :comprehensive
      assert Decimal.equal?(preferences.auto_accept_threshold, Decimal.new("0.95"))
      assert preferences.preferred_providers == ["anthropic", "openai"]
      assert preferences.security_emphasis == :high
      assert preferences.learning_opt_in == true
    end
    
    test "create/1 validates threshold relationships", %{user: user} do
      attrs = %{
        user_id: user.id,
        auto_accept_threshold: Decimal.new("0.5"),
        manual_review_threshold: Decimal.new("0.8")  # Higher than auto accept
      }
      
      assert {:error, %Ash.Error.Invalid{} = error} = UserVerdictPreferences.create(attrs)
      assert error.errors |> List.first() |> Map.get(:message) =~ "manual review threshold must be less than auto accept threshold"
    end
    
    test "create/1 validates budget values", %{user: user} do
      attrs = %{
        user_id: user.id,
        personal_daily_budget: Decimal.new("-25.00"),  # Negative budget
        cost_alert_threshold: Decimal.new("1.5")  # > 1.0
      }
      
      assert {:error, %Ash.Error.Invalid{}} = UserVerdictPreferences.create(attrs)
    end
    
    test "create/1 validates provider preferences", %{user: user} do
      attrs = %{
        user_id: user.id,
        preferred_providers: ["openai"],
        avoid_providers: ["openai"]  # Can't prefer and avoid same provider
      }
      
      assert {:error, %Ash.Error.Invalid{} = error} = UserVerdictPreferences.create(attrs)
      assert error.errors |> List.first() |> Map.get(:message) =~ "cannot prefer and avoid the same provider"
    end
    
    test "create/1 validates custom criteria weights", %{user: user} do
      attrs = %{
        user_id: user.id,
        custom_criteria_weights: %{
          "correctness" => 0.5,
          "security" => 0.3
          # Sum = 0.8, not 1.0
        }
      }
      
      assert {:error, %Ash.Error.Invalid{} = error} = UserVerdictPreferences.create(attrs)
      assert error.errors |> List.first() |> Map.get(:message) =~ "custom criteria weights must sum to 1.0"
    end
  end
  
  describe "user preference queries" do
    test "by_user/1 finds preferences by user ID", %{user: user} do
      {:ok, preferences} = UserVerdictPreferences.create(%{
        user_id: user.id,
        quality_vs_cost_preference: Decimal.new("0.9")
      })
      
      assert {:ok, found_prefs} = UserVerdictPreferences.by_user(user.id)
      assert found_prefs.id == preferences.id
      assert Decimal.equal?(found_prefs.quality_vs_cost_preference, Decimal.new("0.9"))
    end
    
    test "budget_conscious_users/0 finds cost-focused users", %{user: user} do
      {:ok, preferences} = UserVerdictPreferences.create(%{
        user_id: user.id,
        quality_vs_cost_preference: Decimal.new("0.3")  # Cost-focused
      })
      
      budget_conscious = UserVerdictPreferences.budget_conscious_users!()
      assert length(budget_conscious) == 1
      assert List.first(budget_conscious).id == preferences.id
    end
    
    test "quality_focused_users/0 finds quality-focused users", %{user: user} do
      {:ok, preferences} = UserVerdictPreferences.create(%{
        user_id: user.id,
        quality_vs_cost_preference: Decimal.new("0.9")  # Quality-focused
      })
      
      quality_focused = UserVerdictPreferences.quality_focused_users!()
      assert length(quality_focused) == 1
      assert List.first(quality_focused).id == preferences.id
    end
    
    test "high_adaptation_users/1 finds users with high adaptation scores", %{user: user} do
      {:ok, preferences} = UserVerdictPreferences.create(%{
        user_id: user.id,
        adaptation_score: Decimal.new("0.85")
      })
      
      high_adaptation = UserVerdictPreferences.high_adaptation_users!(Decimal.new("0.8"))
      assert length(high_adaptation) == 1
      assert List.first(high_adaptation).id == preferences.id
    end
  end
  
  describe "preference application" do
    test "apply_user_preferences/2 merges user preferences with base configuration", %{user: user} do
      base_config = %{
        enabled: true,
        default_screening_model: "gpt-4o-mini",
        default_detailed_model: "gpt-4o",
        global_daily_budget: Decimal.new("100.00"),
        default_quality_threshold: Decimal.new("0.8"),
        escalation_threshold: Decimal.new("0.6"),
        preferred_providers: ["openai", "anthropic"]
      }
      
      user_preferences = %{
        quality_vs_cost_preference: Decimal.new("0.3"),  # Cost-focused
        personal_daily_budget: Decimal.new("25.00"),
        preferred_providers: ["anthropic"],
        preferred_screening_model: "claude-3-haiku",
        security_emphasis: :high
      }
      
      result = UserVerdictPreferences.apply_user_preferences(base_config, user_preferences)
      
      # Budget should be overridden
      assert Decimal.equal?(result[:global_daily_budget], Decimal.new("25.00"))
      
      # Provider preferences should be applied
      assert result[:preferred_providers] == ["anthropic"]
      assert result[:default_screening_model] == "claude-3-haiku"
      
      # Cost-focused preference should adjust model selection
      assert result[:default_detailed_model] == "gpt-4o-mini"  # Downgraded for cost
      
      # Security emphasis should adjust criteria weights
      criteria_weights = result[:evaluation_criteria_weights]
      assert criteria_weights["security"] > 0.25  # Increased from default
    end
    
    test "apply_user_preferences/2 handles quality-focused preferences", %{user: user} do
      base_config = %{
        escalation_threshold: Decimal.new("0.6"),
        evaluation_criteria_weights: %{
          "correctness" => 0.3,
          "security" => 0.25,
          "maintainability" => 0.2,
          "performance" => 0.15,
          "style" => 0.1
        }
      }
      
      user_preferences = %{
        quality_vs_cost_preference: Decimal.new("0.9"),  # Quality-focused
        performance_emphasis: :critical
      }
      
      result = UserVerdictPreferences.apply_user_preferences(base_config, user_preferences)
      
      # Quality-focused should lower escalation threshold (more detailed evaluations)
      assert Decimal.to_float(result[:escalation_threshold]) < 0.6
      
      # Performance emphasis should increase performance weight
      criteria_weights = result[:evaluation_criteria_weights]
      assert criteria_weights["performance"] > 0.15  # Increased from default
    end
  end
  
  describe "adaptation score updates" do
    test "update_adaptation_score/1 updates score based on behavior analysis", %{user: user} do
      {:ok, preferences} = UserVerdictPreferences.create(%{
        user_id: user.id,
        adaptation_score: Decimal.new("0.5")
      })
      
      {:ok, updated_prefs} = UserVerdictPreferences.update_adaptation_score(preferences, Decimal.new("0.85"))
      
      assert Decimal.equal?(updated_prefs.adaptation_score, Decimal.new("0.85"))
    end
  end
  
  describe "default preferences" do
    test "get_default_preferences/0 returns sensible defaults" do
      defaults = UserVerdictPreferences.get_default_preferences()
      
      assert Decimal.equal?(defaults[:quality_vs_cost_preference], Decimal.new("0.7"))
      assert defaults[:evaluation_detail_level] == :standard
      assert Decimal.equal?(defaults[:auto_accept_threshold], Decimal.new("0.9"))
      assert Decimal.equal?(defaults[:manual_review_threshold], Decimal.new("0.6"))
      assert defaults[:learning_opt_in] == true
      assert defaults[:feedback_frequency] == :weekly
      assert defaults[:cache_preference] == :balanced
    end
  end
end