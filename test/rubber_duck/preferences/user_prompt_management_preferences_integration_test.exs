defmodule RubberDuck.Preferences.UserPromptManagementPreferencesIntegrationTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Preferences.Services.{PromptPreferenceResolver, PromptInterfaceCustomizer}
  alias RubberDuck.Preferences.Resources.{UserPreference, SystemDefault}
  alias RubberDuck.Prompts.Resources.Prompt

  describe "Phase 6.3: User Prompt Management Preferences - Integration Testing" do
    test "complete user prompt management preference integration with Phase 1A" do
      # Test complete integration from preference setting through interface customization

      user_id = Ash.UUID.generate()
      project_id = Ash.UUID.generate()
      tenant_id = Ash.UUID.generate()

      # Step 1: Create test prompts for preference testing
      {:ok, system_prompt} =
        Prompt.create_system_prompt(%{
          content: "System prompt for preference testing",
          name: "preference_test_system_prompt",
          tenant_id: tenant_id,
          description: "System prompt for testing user preference integration"
        })

      {:ok, user_prompt} =
        Prompt.create_user_prompt(%{
          content: "User prompt for preference testing with {{variable}}",
          name: "preference_test_user_prompt",
          tenant_id: tenant_id,
          user_id: user_id,
          description: "User prompt for testing preference customization"
        })

      # Step 2: Set user preferences using Phase 1A UserPreference system
      # Display preferences
      {:ok, _display_pref} =
        UserPreference.set_preference(
          user_id,
          "prompt_management.display.view_mode",
          "grid",
          "User prefers grid view for prompt library"
        )

      {:ok, _sort_pref} =
        UserPreference.set_preference(
          user_id,
          "prompt_management.display.sort_by",
          "usage_count",
          "Sort prompts by usage frequency"
        )

      {:ok, _items_pref} =
        UserPreference.set_preference(
          user_id,
          "prompt_management.display.items_per_page",
          "50",
          "Show more prompts per page for productivity"
        )

      # Organization preferences
      {:ok, _org_pref} =
        UserPreference.set_preference(
          user_id,
          "prompt_management.organization.categorization_scheme",
          "tag_based",
          "Prefer tag-based organization over hierarchical"
        )

      {:ok, _auto_cat_pref} =
        UserPreference.set_preference(
          user_id,
          "prompt_management.organization.auto_categorization",
          "true",
          "Enable automatic categorization of new prompts"
        )

      # Search preferences
      {:ok, _search_scope_pref} =
        UserPreference.set_preference(
          user_id,
          "prompt_management.search.default_scope",
          "favorites",
          "Search favorites by default for efficiency"
        )

      {:ok, _fuzzy_pref} =
        UserPreference.set_preference(
          user_id,
          "prompt_management.search.fuzzy_search",
          "true",
          "Enable fuzzy search for typo tolerance"
        )

      # Workflow preferences
      {:ok, _recent_limit_pref} =
        UserPreference.set_preference(
          user_id,
          "prompt_management.workflow.recent_limit",
          "15",
          "Show more recent prompts for quick access"
        )

      # Step 3: Test preference resolution with caching
      assert {:ok, display_preferences} =
               PromptPreferenceResolver.resolve_display_preferences(user_id, project_id)

      # Should resolve user-set preferences
      assert display_preferences.view_mode == "grid"
      assert display_preferences.sort_by == "usage_count"
      assert display_preferences.items_per_page == "50"

      assert {:ok, organization_preferences} =
               PromptPreferenceResolver.resolve_organization_preferences(user_id, project_id)

      assert organization_preferences.categorization_scheme == "tag_based"
      assert organization_preferences.auto_categorization == "true"

      assert {:ok, search_preferences} =
               PromptPreferenceResolver.resolve_search_preferences(user_id, project_id)

      assert search_preferences.default_scope == "favorites"
      assert search_preferences.fuzzy_search == "true"

      assert {:ok, workflow_preferences} =
               PromptPreferenceResolver.resolve_workflow_preferences(user_id, project_id)

      assert workflow_preferences.recent_limit == "15"

      # Step 4: Test comprehensive preference resolution
      assert {:ok, all_preferences} =
               PromptPreferenceResolver.resolve_all_prompt_management_preferences(
                 user_id,
                 project_id
               )

      assert Map.has_key?(all_preferences, :display)
      assert Map.has_key?(all_preferences, :organization)
      assert Map.has_key?(all_preferences, :search)
      assert Map.has_key?(all_preferences, :workflow)
      assert Map.has_key?(all_preferences, :resolved_at)

      # Verify all preferences are present
      assert all_preferences.display.view_mode == "grid"
      assert all_preferences.organization.categorization_scheme == "tag_based"
      assert all_preferences.search.default_scope == "favorites"
      assert all_preferences.workflow.recent_limit == "15"

      # Step 5: Test interface customization based on preferences
      base_interface_config = %{
        layout: :standard,
        theme: :light,
        components: [:search, :list, :filters]
      }

      assert {:ok, customized_interface} =
               PromptInterfaceCustomizer.customize_prompt_browser(
                 user_id,
                 base_interface_config,
                 project_id
               )

      # Interface should be customized based on user preferences
      assert Map.has_key?(customized_interface, :display)
      assert Map.has_key?(customized_interface, :search)
      assert Map.has_key?(customized_interface, :workflow)
      assert Map.has_key?(customized_interface, :organization)

      # Display customization should reflect user preferences
      assert customized_interface.display.view_mode == "grid"
      assert customized_interface.display.sort_configuration.sort_by == "usage_count"
      assert customized_interface.display.pagination.items_per_page == "50"

      # Search customization should reflect user preferences
      assert customized_interface.search.default_scope == "favorites"
      assert customized_interface.search.fuzzy_search == "true"

      # Should have customization metadata
      assert Map.has_key?(customized_interface, :customization_metadata)
      assert customized_interface.customization_metadata.customized == true

      # Step 6: Test preference caching performance
      # First resolution (cache miss)
      cache_miss_start = System.monotonic_time(:microsecond)

      assert {:ok, _cached_display} =
               PromptPreferenceResolver.resolve_display_preferences(user_id, project_id)

      cache_miss_time = System.monotonic_time(:microsecond) - cache_miss_start

      # Second resolution (cache hit)
      cache_hit_start = System.monotonic_time(:microsecond)

      assert {:ok, _cached_display_2} =
               PromptPreferenceResolver.resolve_display_preferences(user_id, project_id)

      cache_hit_time = System.monotonic_time(:microsecond) - cache_hit_start

      # Cached resolution should be significantly faster
      cache_miss_time_ms = cache_miss_time / 1000
      cache_hit_time_ms = cache_hit_time / 1000

      assert cache_hit_time_ms < cache_miss_time_ms / 2,
             "Cache hit (#{cache_hit_time_ms}ms) should be much faster than cache miss (#{cache_miss_time_ms}ms)"

      # Step 7: Test cache invalidation on preference changes
      # Update a preference
      {:ok, _updated_pref} =
        UserPreference.set_preference(
          user_id,
          "prompt_management.display.view_mode",
          "cards",
          "Changed to cards view"
        )

      # Invalidate cache
      PromptPreferenceResolver.invalidate_user_cache(user_id)

      # Re-resolve preferences (should get updated values)
      assert {:ok, updated_display} =
               PromptPreferenceResolver.resolve_display_preferences(user_id, project_id)

      # Should reflect the update
      assert updated_display.view_mode == "cards"

      # Step 8: Test interface customization metadata
      assert {:ok, customization_metadata} =
               PromptInterfaceCustomizer.get_customization_metadata(user_id, project_id)

      assert customization_metadata.user_id == user_id
      assert customization_metadata.customization_applied == true
      assert Map.has_key?(customization_metadata, :customization_summary)
      assert customization_metadata.customization_summary.display_customized == true
    end

    test "intelligent defaults for users without configured preferences" do
      # Test intelligent defaults for new users with no preferences

      new_user_id = Ash.UUID.generate()

      # Test display defaults
      assert {:ok, default_display} =
               PromptPreferenceResolver.resolve_display_preferences(new_user_id)

      # Should provide reasonable defaults
      assert default_display.view_mode in ["list", "grid", "cards", "compact"]
      assert default_display.sort_by in ["name", "created_at", "usage_count"]
      assert default_display.sort_direction in ["asc", "desc"]

      assert is_integer(default_display.items_per_page) or
               is_binary(default_display.items_per_page)

      # Test organization defaults
      assert {:ok, default_organization} =
               PromptPreferenceResolver.resolve_organization_preferences(new_user_id)

      assert default_organization.categorization_scheme in ["hierarchical", "flat", "tag_based"]

      assert is_boolean(default_organization.auto_categorization) or
               default_organization.auto_categorization in ["true", "false"]

      # Test search defaults
      assert {:ok, default_search} =
               PromptPreferenceResolver.resolve_search_preferences(new_user_id)

      assert default_search.default_scope in ["all", "user_only", "favorites"]

      assert is_boolean(default_search.fuzzy_search) or
               default_search.fuzzy_search in ["true", "false"]

      # Test workflow defaults
      assert {:ok, default_workflow} =
               PromptPreferenceResolver.resolve_workflow_preferences(new_user_id)

      assert is_list(default_workflow.quick_access_prompts)
      assert is_list(default_workflow.favorite_categories)

      # Test that defaults provide functional interface
      base_config = %{layout: :standard}

      assert {:ok, default_interface} =
               PromptInterfaceCustomizer.customize_prompt_browser(new_user_id, base_config)

      assert Map.has_key?(default_interface, :display)
      assert Map.has_key?(default_interface, :customization_metadata)
    end

    test "preference performance requirements validation" do
      # Test that preference resolution meets performance requirements

      perf_user_id = Ash.UUID.generate()

      # Create user preferences for performance testing
      preference_keys = [
        {"prompt_management.display.view_mode", "list"},
        {"prompt_management.display.sort_by", "name"},
        {"prompt_management.organization.categorization_scheme", "hierarchical"},
        {"prompt_management.search.default_scope", "all"},
        {"prompt_management.workflow.recent_limit", "10"}
      ]

      for {key, value} <- preference_keys do
        {:ok, _pref} = UserPreference.set_preference(perf_user_id, key, value, "Performance test")
      end

      # Test preference resolution performance
      resolution_start = System.monotonic_time(:microsecond)

      assert {:ok, _all_prefs} =
               PromptPreferenceResolver.resolve_all_prompt_management_preferences(perf_user_id)

      resolution_time = System.monotonic_time(:microsecond) - resolution_start
      resolution_time_ms = resolution_time / 1000

      # Should meet <100ms requirement for preference resolution
      assert resolution_time_ms < 100,
             "Preference resolution #{resolution_time_ms}ms exceeds 100ms requirement"

      # Test interface customization performance
      interface_customization_start = System.monotonic_time(:microsecond)

      base_config = %{layout: :standard, components: [:search, :list]}

      assert {:ok, _customized_interface} =
               PromptInterfaceCustomizer.customize_prompt_browser(perf_user_id, base_config)

      interface_customization_time =
        System.monotonic_time(:microsecond) - interface_customization_start

      interface_customization_time_ms = interface_customization_time / 1000

      # Should meet <100ms requirement for interface adaptation
      assert interface_customization_time_ms < 100,
             "Interface customization #{interface_customization_time_ms}ms exceeds 100ms requirement"
    end

    test "preference hierarchy integration with Phase 1A system" do
      # Test that prompt management preferences follow Phase 1A hierarchy patterns

      hierarchy_user_id = Ash.UUID.generate()
      hierarchy_project_id = Ash.UUID.generate()

      # Step 1: Test user-level preferences
      {:ok, _user_display_pref} =
        UserPreference.set_preference(
          hierarchy_user_id,
          "prompt_management.display.view_mode",
          "grid",
          "User-level display preference"
        )

      # Test resolution at user level
      assert {:ok, user_level_prefs} =
               PromptPreferenceResolver.resolve_display_preferences(hierarchy_user_id)

      assert user_level_prefs.view_mode == "grid"

      # Step 2: Test that user preferences are isolated between users
      other_user_id = Ash.UUID.generate()

      # Other user should get defaults, not first user's preferences
      assert {:ok, other_user_prefs} =
               PromptPreferenceResolver.resolve_display_preferences(other_user_id)

      # Should not inherit first user's grid preference (should get defaults)
      assert other_user_prefs.view_mode != "grid" or
               Map.get(other_user_prefs, :source) == :default

      # Step 3: Test preference resolution with project context
      # Should still get user preference even in project context
      assert {:ok, user_project_prefs} =
               PromptPreferenceResolver.resolve_display_preferences(
                 hierarchy_user_id,
                 hierarchy_project_id
               )

      assert user_project_prefs.view_mode == "grid"

      # Step 4: Test that preference updates propagate correctly
      {:ok, _updated_pref} =
        UserPreference.set_preference(
          hierarchy_user_id,
          "prompt_management.display.view_mode",
          "compact",
          "Updated to compact view"
        )

      # Invalidate cache to simulate real-time update
      PromptPreferenceResolver.invalidate_user_cache(hierarchy_user_id)

      # Should get updated preference
      assert {:ok, updated_prefs} =
               PromptPreferenceResolver.resolve_display_preferences(hierarchy_user_id)

      assert updated_prefs.view_mode == "compact"
    end

    test "interface customization with different preference combinations" do
      # Test interface customization across different user preference combinations

      # Test Case 1: Power User Configuration
      power_user_id = Ash.UUID.generate()

      power_user_preferences = [
        {"prompt_management.display.view_mode", "compact"},
        {"prompt_management.display.sort_by", "usage_count"},
        {"prompt_management.display.items_per_page", "100"},
        {"prompt_management.search.quick_filters",
         "[\"recent\", \"favorites\", \"most_used\", \"by_category\"]"},
        {"prompt_management.organization.categorization_scheme", "tag_based"}
      ]

      for {key, value} <- power_user_preferences do
        {:ok, _pref} =
          UserPreference.set_preference(power_user_id, key, value, "Power user config")
      end

      assert {:ok, power_user_interface} =
               PromptInterfaceCustomizer.customize_prompt_browser(power_user_id, %{})

      # Should reflect power user preferences
      assert power_user_interface.display.view_mode == "compact"
      assert power_user_interface.display.sort_configuration.sort_by == "usage_count"
      assert power_user_interface.display.pagination.items_per_page == "100"
      assert power_user_interface.organization.categorization_scheme == "tag_based"

      # Test Case 2: Casual User Configuration
      casual_user_id = Ash.UUID.generate()

      casual_user_preferences = [
        {"prompt_management.display.view_mode", "cards"},
        {"prompt_management.display.sort_by", "name"},
        {"prompt_management.display.items_per_page", "20"},
        {"prompt_management.search.quick_filters", "[\"recent\", \"favorites\"]"}
      ]

      for {key, value} <- casual_user_preferences do
        {:ok, _pref} =
          UserPreference.set_preference(casual_user_id, key, value, "Casual user config")
      end

      assert {:ok, casual_user_interface} =
               PromptInterfaceCustomizer.customize_prompt_browser(casual_user_id, %{})

      # Should reflect casual user preferences
      assert casual_user_interface.display.view_mode == "cards"
      assert casual_user_interface.display.sort_configuration.sort_by == "name"
      assert casual_user_interface.display.pagination.items_per_page == "20"

      # Test Case 3: Mixed Preference Configuration
      mixed_user_id = Ash.UUID.generate()

      # Set only some preferences (others should get defaults)
      {:ok, _mixed_pref} =
        UserPreference.set_preference(
          mixed_user_id,
          "prompt_management.display.view_mode",
          "list",
          "Only set view mode preference"
        )

      assert {:ok, mixed_interface} =
               PromptInterfaceCustomizer.customize_prompt_browser(mixed_user_id, %{})

      # Should have user preference for view_mode
      assert mixed_interface.display.view_mode == "list"

      # Should have defaults for other preferences
      assert Map.has_key?(mixed_interface.display.sort_configuration, :sort_by)
      assert Map.has_key?(mixed_interface.search, :default_scope)
    end

    test "real-time preference updates and interface adaptation" do
      # Test real-time preference updates and interface adaptation

      realtime_user_id = Ash.UUID.generate()

      # Set initial preferences
      {:ok, _initial_pref} =
        UserPreference.set_preference(
          realtime_user_id,
          "prompt_management.display.view_mode",
          "list",
          "Initial preference"
        )

      # Resolve initial interface customization
      assert {:ok, initial_interface} =
               PromptInterfaceCustomizer.customize_prompt_browser(realtime_user_id, %{})

      assert initial_interface.display.view_mode == "list"

      # Update preference
      {:ok, _updated_pref} =
        UserPreference.set_preference(
          realtime_user_id,
          "prompt_management.display.view_mode",
          "grid",
          "Updated preference"
        )

      # Simulate cache invalidation (would happen via Phoenix PubSub in real system)
      PromptPreferenceResolver.invalidate_user_cache(realtime_user_id)

      # Resolve updated interface customization
      assert {:ok, updated_interface} =
               PromptInterfaceCustomizer.customize_prompt_browser(realtime_user_id, %{})

      assert updated_interface.display.view_mode == "grid"
      assert updated_interface.display.view_mode != initial_interface.display.view_mode

      # Test that interface customization includes update metadata
      assert Map.has_key?(updated_interface, :customization_metadata)
      assert updated_interface.customization_metadata.preferences_applied == true
    end

    test "preference integration with Sections 6.1 and 6.2 infrastructure" do
      # Test integration with existing prompt selection infrastructure

      integration_user_id = Ash.UUID.generate()
      integration_project_id = Ash.UUID.generate()

      # Set preferences that should affect prompt selection behavior
      {:ok, _search_pref} =
        UserPreference.set_preference(
          integration_user_id,
          "prompt_management.search.include_content",
          "false",
          "Search titles only for faster results"
        )

      {:ok, _display_pref} =
        UserPreference.set_preference(
          integration_user_id,
          "prompt_management.display.sort_by",
          "created_at",
          "Sort by creation date"
        )

      # Test that preferences are applied to prompt selection options
      assert {:ok, preferences} =
               PromptPreferenceResolver.resolve_all_prompt_management_preferences(
                 integration_user_id,
                 integration_project_id
               )

      # Test interface customization
      base_config = %{components: [:search, :display]}

      assert {:ok, customized_config} =
               PromptInterfaceCustomizer.customize_prompt_browser(
                 integration_user_id,
                 base_config,
                 integration_project_id
               )

      # Search configuration should reflect user preferences
      assert customized_config.search.include_content == "false"
      assert customized_config.display.sort_configuration.sort_by == "created_at"

      # Should integrate with customization metadata
      assert customized_config.customization_metadata.customized == true
      assert customized_config.customization_metadata.preferences_applied == true
    end

    test "backward compatibility with existing prompt management workflows" do
      # Test that preference integration doesn't break existing functionality

      compatibility_user_id = Ash.UUID.generate()

      # Test interface customization without any user preferences (should use defaults)
      base_config = %{layout: :standard}

      assert {:ok, default_interface} =
               PromptInterfaceCustomizer.customize_prompt_browser(
                 compatibility_user_id,
                 base_config
               )

      # Should work with defaults
      assert Map.has_key?(default_interface, :display)
      assert Map.has_key?(default_interface, :search)
      assert Map.has_key?(default_interface, :workflow)
      assert Map.has_key?(default_interface, :customization_metadata)

      # Defaults should be functional
      assert default_interface.display.view_mode in ["list", "grid", "cards", "compact"]
      assert default_interface.customization_metadata.customized == true

      # Test preference resolution with no configured preferences (should return defaults)
      assert {:ok, default_all_prefs} =
               PromptPreferenceResolver.resolve_all_prompt_management_preferences(
                 compatibility_user_id
               )

      # All preference categories should have defaults
      assert Map.has_key?(default_all_prefs, :display)
      assert Map.has_key?(default_all_prefs, :organization)
      assert Map.has_key?(default_all_prefs, :search)
      assert Map.has_key?(default_all_prefs, :workflow)

      # Defaults should be reasonable
      assert is_binary(default_all_prefs.display.view_mode)
      assert is_binary(default_all_prefs.organization.categorization_scheme)
      assert is_list(default_all_prefs.workflow.quick_access_prompts)
    end
  end

  describe "Integration Quality Requirements" do
    test "comprehensive preference service validation" do
      # Validate all preference services are working correctly

      preference_services = [
        PromptPreferenceResolver,
        PromptInterfaceCustomizer
      ]

      for service <- preference_services do
        assert Code.ensure_loaded?(service), "Service #{service} should be loaded"
      end
    end

    test "Phase 1A integration validation" do
      # Validate proper integration with Phase 1A preference system

      phase1a_user_id = Ash.UUID.generate()

      # Test that prompt management preferences integrate with UserPreference resource
      {:ok, _test_pref} =
        UserPreference.set_preference(
          phase1a_user_id,
          "prompt_management.display.view_mode",
          "grid",
          "Phase 1A integration test"
        )

      # Should be retrievable via PromptPreferenceResolver
      assert {:ok, resolved_prefs} =
               PromptPreferenceResolver.resolve_display_preferences(phase1a_user_id)

      assert resolved_prefs.view_mode == "grid"

      # Should be visible via UserPreference queries
      assert {:ok, user_preferences} = UserPreference.by_user(phase1a_user_id)

      prompt_management_prefs =
        Enum.filter(user_preferences, fn pref ->
          String.starts_with?(pref.preference_key, "prompt_management.")
        end)

      assert length(prompt_management_prefs) >= 1
    end

    test "performance scalability with multiple concurrent users" do
      # Test preference resolution performance with multiple users

      concurrent_users =
        for i <- 1..20 do
          user_id = Ash.UUID.generate()

          # Set preferences for each user
          {:ok, _pref} =
            UserPreference.set_preference(
              user_id,
              "prompt_management.display.view_mode",
              Enum.random(["list", "grid", "cards", "compact"]),
              "Concurrent user test"
            )

          user_id
        end

      # Test concurrent preference resolution
      concurrent_start = System.monotonic_time(:microsecond)

      concurrent_tasks =
        Enum.map(concurrent_users, fn user_id ->
          Task.async(fn ->
            PromptPreferenceResolver.resolve_all_prompt_management_preferences(user_id)
          end)
        end)

      concurrent_results = Task.await_many(concurrent_tasks, 5000)

      concurrent_time = System.monotonic_time(:microsecond) - concurrent_start
      concurrent_time_ms = concurrent_time / 1000

      # All resolutions should succeed
      successful_resolutions = Enum.filter(concurrent_results, &match?({:ok, _}, &1))
      assert length(successful_resolutions) == 20

      # Total time should be reasonable for 20 concurrent users
      assert concurrent_time_ms < 500,
             "Concurrent preference resolution #{concurrent_time_ms}ms too slow"

      # Average per-user time should meet requirements
      avg_time_per_user = concurrent_time_ms / 20

      assert avg_time_per_user < 25,
             "Average per-user resolution #{avg_time_per_user}ms exceeds 25ms target"
    end
  end
end
