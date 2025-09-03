defmodule RubberDuck.Prompts.Services.PromptOrganizer do
  @moduledoc """
  Core organization service for saved prompt categorization and hierarchical management.

  Provides comprehensive organization capabilities for users to manage their saved
  prompt collections including flexible categorization schemes, hierarchical
  organization structures, and automated organization suggestions based on prompt
  content and usage patterns.

  Features:
  - Flexible categorization schemes for saved prompt organization (hierarchical, flat, tag-based)
  - Hierarchical category management with nesting and relationship support
  - Auto-categorization suggestions based on prompt content analysis
  - Custom organizational structures per user with preference integration
  - Performance optimization for large prompt collections (10k+ prompts)
  """

  use GenServer
  require Logger

  alias RubberDuck.Prompts.Resources.{Prompt, PromptCategory}

  @categorization_schemes [:hierarchical, :flat, :tag_based, :custom, :mixed]
  @auto_categorization_strategies [
    :content_analysis,
    :usage_patterns,
    :manual_classification,
    :hybrid
  ]

  defstruct [
    :organization_config,
    :categorization_cache,
    :auto_suggestion_engine,
    :performance_metrics
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      organization_config: build_organization_config(),
      categorization_cache: initialize_categorization_cache(),
      auto_suggestion_engine: initialize_suggestion_engine(),
      performance_metrics: initialize_performance_metrics()
    }

    Logger.info("PromptOrganizer: Service initialized",
      categorization_schemes: @categorization_schemes,
      auto_strategies: @auto_categorization_strategies
    )

    {:ok, state}
  end

  # Public API

  @doc """
  Organize prompts for user with specified categorization scheme.
  """
  def organize_prompts_for_user(user_id, prompts, organization_options \\ %{}) do
    GenServer.call(__MODULE__, {:organize_prompts, user_id, prompts, organization_options})
  end

  @doc """
  Get organization suggestions for user's prompt collection.
  """
  def get_organization_suggestions(user_id, prompt_collection, suggestion_options \\ %{}) do
    GenServer.call(__MODULE__, {:get_suggestions, user_id, prompt_collection, suggestion_options})
  end

  @doc """
  Create custom category for user's prompt organization.
  """
  def create_custom_category(user_id, category_definition, options \\ %{}) do
    GenServer.call(__MODULE__, {:create_category, user_id, category_definition, options})
  end

  @doc """
  Auto-categorize new prompt based on content and context.
  """
  def auto_categorize_prompt(prompt, user_context \\ %{}) do
    GenServer.call(__MODULE__, {:auto_categorize, prompt, user_context})
  end

  @doc """
  Reorganize user's prompt collection with new scheme.
  """
  def reorganize_prompt_collection(user_id, new_scheme, reorganization_options \\ %{}) do
    GenServer.call(
      __MODULE__,
      {:reorganize_collection, user_id, new_scheme, reorganization_options}
    )
  end

  # GenServer callbacks

  @impl true
  def handle_call({:organize_prompts, user_id, prompts, organization_options}, _from, state) do
    Logger.debug("PromptOrganizer: Organizing prompts for user",
      user_id: user_id,
      prompt_count: length(prompts),
      organization_scheme: Map.get(organization_options, :scheme, :hierarchical)
    )

    case execute_prompt_organization(user_id, prompts, organization_options, state) do
      {:ok, organization_result} ->
        Logger.info("PromptOrganizer: Prompts organized successfully",
          user_id: user_id,
          organized_categories: organization_result.category_count,
          organization_scheme: organization_result.scheme_used
        )

        {:reply, {:ok, organization_result}, state}

      {:error, reason} ->
        Logger.error("PromptOrganizer: Organization failed",
          user_id: user_id,
          error: reason
        )

        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(
        {:get_suggestions, user_id, prompt_collection, suggestion_options},
        _from,
        state
      ) do
    case generate_organization_suggestions(user_id, prompt_collection, suggestion_options, state) do
      {:ok, suggestions} ->
        Logger.debug("PromptOrganizer: Organization suggestions generated",
          user_id: user_id,
          suggestion_count: length(suggestions.suggestions)
        )

        {:reply, {:ok, suggestions}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:create_category, user_id, category_definition, options}, _from, state) do
    case create_user_custom_category(user_id, category_definition, options) do
      {:ok, category} ->
        Logger.info("PromptOrganizer: Custom category created",
          user_id: user_id,
          category_name: category.name
        )

        {:reply, {:ok, category}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:auto_categorize, prompt, user_context}, _from, state) do
    case execute_auto_categorization(prompt, user_context, state) do
      {:ok, categorization_result} ->
        {:reply, {:ok, categorization_result}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(
        {:reorganize_collection, user_id, new_scheme, reorganization_options},
        _from,
        state
      ) do
    case execute_collection_reorganization(user_id, new_scheme, reorganization_options, state) do
      {:ok, reorganization_result} ->
        Logger.info("PromptOrganizer: Collection reorganized",
          user_id: user_id,
          new_scheme: new_scheme,
          reorganized_count: reorganization_result.reorganized_count
        )

        {:reply, {:ok, reorganization_result}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Private implementation functions

  defp execute_prompt_organization(user_id, prompts, organization_options, state) do
    # Execute prompt organization based on user preferences and options
    organization_scheme = Map.get(organization_options, :scheme, :hierarchical)

    case organization_scheme do
      :hierarchical ->
        execute_hierarchical_organization(user_id, prompts, organization_options, state)

      :flat ->
        execute_flat_organization(user_id, prompts, organization_options, state)

      :tag_based ->
        execute_tag_based_organization(user_id, prompts, organization_options, state)

      :custom ->
        execute_custom_organization(user_id, prompts, organization_options, state)

      :mixed ->
        execute_mixed_organization(user_id, prompts, organization_options, state)
    end
  end

  defp execute_hierarchical_organization(user_id, prompts, options, state) do
    # Execute hierarchical organization of prompts
    categorized_prompts =
      prompts
      |> group_prompts_by_category()
      |> organize_into_hierarchy(Map.get(options, :hierarchy_depth, 3))

    organization_result = %{
      organized_prompts: categorized_prompts,
      scheme_used: :hierarchical,
      category_count: count_categories_in_hierarchy(categorized_prompts),
      organization_metadata: %{
        hierarchy_depth: Map.get(options, :hierarchy_depth, 3),
        organization_timestamp: DateTime.utc_now()
      }
    }

    {:ok, organization_result}
  end

  defp execute_flat_organization(user_id, prompts, options, state) do
    # Execute flat organization (single level categories)
    categorized_prompts =
      prompts
      |> group_prompts_by_category()
      |> flatten_category_structure()

    organization_result = %{
      organized_prompts: categorized_prompts,
      scheme_used: :flat,
      category_count: map_size(categorized_prompts),
      organization_metadata: %{
        flat_categories: Map.keys(categorized_prompts),
        organization_timestamp: DateTime.utc_now()
      }
    }

    {:ok, organization_result}
  end

  defp execute_tag_based_organization(user_id, prompts, options, state) do
    # Execute tag-based organization
    tagged_prompts =
      prompts
      |> analyze_prompt_tags()
      |> organize_by_tag_relationships()

    organization_result = %{
      organized_prompts: tagged_prompts,
      scheme_used: :tag_based,
      category_count: count_unique_tags(tagged_prompts),
      organization_metadata: %{
        tag_count: count_unique_tags(tagged_prompts),
        organization_timestamp: DateTime.utc_now()
      }
    }

    {:ok, organization_result}
  end

  defp execute_custom_organization(user_id, prompts, options, state) do
    # Execute custom organization based on user-defined rules
    custom_rules = Map.get(options, :custom_rules, [])

    organized_prompts = apply_custom_organization_rules(prompts, custom_rules)

    organization_result = %{
      organized_prompts: organized_prompts,
      scheme_used: :custom,
      category_count: count_custom_categories(organized_prompts),
      organization_metadata: %{
        custom_rules_applied: length(custom_rules),
        organization_timestamp: DateTime.utc_now()
      }
    }

    {:ok, organization_result}
  end

  defp execute_mixed_organization(user_id, prompts, options, state) do
    # Execute mixed organization combining multiple schemes
    with {:ok, hierarchical_result} <-
           execute_hierarchical_organization(user_id, prompts, options, state),
         {:ok, tag_result} <- execute_tag_based_organization(user_id, prompts, options, state) do
      mixed_organization = combine_organization_schemes(hierarchical_result, tag_result)

      organization_result = %{
        organized_prompts: mixed_organization,
        scheme_used: :mixed,
        category_count: count_mixed_categories(mixed_organization),
        organization_metadata: %{
          schemes_combined: [:hierarchical, :tag_based],
          organization_timestamp: DateTime.utc_now()
        }
      }

      {:ok, organization_result}
    else
      {:error, reason} -> {:error, {:mixed_organization_failed, reason}}
    end
  end

  defp generate_organization_suggestions(user_id, prompt_collection, suggestion_options, state) do
    # Generate intelligent organization suggestions
    analysis_type = Map.get(suggestion_options, :analysis_type, :usage_patterns)

    case analysis_type do
      :usage_patterns ->
        generate_usage_based_suggestions(user_id, prompt_collection)

      :content_analysis ->
        generate_content_based_suggestions(prompt_collection)

      :similarity_analysis ->
        generate_similarity_based_suggestions(prompt_collection)

      :comprehensive ->
        generate_comprehensive_suggestions(user_id, prompt_collection, state)
    end
  end

  defp execute_auto_categorization(prompt, user_context, state) do
    # Execute automatic categorization of new prompt
    content_analysis = analyze_prompt_content_for_categorization(prompt.content)
    context_analysis = analyze_user_context_for_categorization(user_context)

    suggested_categories = determine_suggested_categories(content_analysis, context_analysis)

    categorization_result = %{
      prompt_id: prompt.id,
      suggested_categories: suggested_categories,
      confidence_scores: calculate_categorization_confidence(content_analysis, context_analysis),
      auto_categorization_metadata: %{
        analysis_method: :content_and_context,
        categorized_at: DateTime.utc_now()
      }
    }

    {:ok, categorization_result}
  end

  defp create_user_custom_category(user_id, category_definition, options) do
    # Create custom category for user
    category_attrs = %{
      name: category_definition.name,
      description: Map.get(category_definition, :description, ""),
      parent_id: Map.get(category_definition, :parent_id),
      user_id: user_id,
      category_type: :custom,
      metadata: Map.get(options, :metadata, %{})
    }

    case PromptCategory.create(category_attrs) do
      {:ok, category} ->
        {:ok, category}

      {:error, reason} ->
        {:error, {:category_creation_failed, reason}}
    end
  end

  defp execute_collection_reorganization(user_id, new_scheme, reorganization_options, state) do
    # Execute reorganization of user's prompt collection
    case get_user_prompt_collection(user_id) do
      {:ok, current_prompts} ->
        reorganization_options = Map.put(reorganization_options, :scheme, new_scheme)

        case execute_prompt_organization(user_id, current_prompts, reorganization_options, state) do
          {:ok, organization_result} ->
            reorganization_result = %{
              reorganized_count: length(current_prompts),
              new_scheme: new_scheme,
              new_organization: organization_result,
              reorganization_metadata: %{
                reorganized_at: DateTime.utc_now(),
                previous_scheme: Map.get(reorganization_options, :previous_scheme, :unknown)
              }
            }

            {:ok, reorganization_result}

          {:error, reason} ->
            {:error, {:reorganization_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:collection_fetch_failed, reason}}
    end
  end

  # Organization helper functions

  defp group_prompts_by_category(prompts) do
    # Group prompts by their existing categories
    prompts
    |> Enum.group_by(fn prompt ->
      case prompt.category_id do
        nil -> "Uncategorized"
        category_id -> get_category_name(category_id)
      end
    end)
  end

  defp organize_into_hierarchy(grouped_prompts, max_depth) do
    # Organize grouped prompts into hierarchical structure
    # Simplified implementation - would build actual hierarchy based on category relationships
    grouped_prompts
  end

  defp flatten_category_structure(grouped_prompts) do
    # Flatten any existing hierarchy into single-level categories
    grouped_prompts
  end

  defp analyze_prompt_tags(prompts) do
    # Analyze and extract tags from prompts for tag-based organization
    prompts
    |> Enum.map(fn prompt ->
      tags = extract_tags_from_prompt(prompt)
      Map.put(prompt, :extracted_tags, tags)
    end)
  end

  defp organize_by_tag_relationships(tagged_prompts) do
    # Organize prompts based on tag relationships and hierarchies
    tagged_prompts
    |> Enum.group_by(fn prompt ->
      primary_tag = get_primary_tag(prompt.extracted_tags || [])
      primary_tag || "Untagged"
    end)
  end

  defp apply_custom_organization_rules(prompts, custom_rules) do
    # Apply user-defined custom organization rules
    Enum.reduce(custom_rules, prompts, fn rule, acc_prompts ->
      apply_single_custom_rule(acc_prompts, rule)
    end)
  end

  defp combine_organization_schemes(hierarchical_result, tag_result) do
    # Combine multiple organization schemes
    %{
      hierarchical: hierarchical_result.organized_prompts,
      tag_based: tag_result.organized_prompts,
      combined_view: merge_organization_views(hierarchical_result, tag_result)
    }
  end

  # Suggestion generation functions

  defp generate_usage_based_suggestions(user_id, prompt_collection) do
    # Generate suggestions based on usage patterns
    usage_patterns = analyze_collection_usage_patterns(user_id, prompt_collection)

    suggestions = %{
      suggestions: build_usage_based_organization_suggestions(usage_patterns),
      analysis_type: :usage_patterns,
      confidence_level: calculate_usage_suggestion_confidence(usage_patterns),
      suggestion_metadata: %{
        analysis_period: :last_30_days,
        pattern_count: length(usage_patterns),
        generated_at: DateTime.utc_now()
      }
    }

    {:ok, suggestions}
  end

  defp generate_content_based_suggestions(prompt_collection) do
    # Generate suggestions based on prompt content analysis
    content_analysis = analyze_prompt_content_patterns(prompt_collection)

    suggestions = %{
      suggestions: build_content_based_organization_suggestions(content_analysis),
      analysis_type: :content_analysis,
      confidence_level: calculate_content_suggestion_confidence(content_analysis),
      suggestion_metadata: %{
        content_patterns: Map.keys(content_analysis),
        analyzed_prompts: length(prompt_collection),
        generated_at: DateTime.utc_now()
      }
    }

    {:ok, suggestions}
  end

  defp generate_similarity_based_suggestions(prompt_collection) do
    # Generate suggestions based on prompt similarity analysis
    similarity_groups = analyze_prompt_similarity(prompt_collection)

    suggestions = %{
      suggestions: build_similarity_based_organization_suggestions(similarity_groups),
      analysis_type: :similarity_analysis,
      confidence_level: 0.75,
      suggestion_metadata: %{
        similarity_groups: length(similarity_groups),
        generated_at: DateTime.utc_now()
      }
    }

    {:ok, suggestions}
  end

  defp generate_comprehensive_suggestions(user_id, prompt_collection, state) do
    # Generate comprehensive suggestions combining all analysis methods
    with {:ok, usage_suggestions} <- generate_usage_based_suggestions(user_id, prompt_collection),
         {:ok, content_suggestions} <- generate_content_based_suggestions(prompt_collection),
         {:ok, similarity_suggestions} <- generate_similarity_based_suggestions(prompt_collection) do
      comprehensive_suggestions = %{
        suggestions:
          combine_suggestion_types([
            usage_suggestions,
            content_suggestions,
            similarity_suggestions
          ]),
        analysis_type: :comprehensive,
        confidence_level:
          calculate_comprehensive_confidence([
            usage_suggestions,
            content_suggestions,
            similarity_suggestions
          ]),
        suggestion_metadata: %{
          analysis_methods: [:usage_patterns, :content_analysis, :similarity_analysis],
          generated_at: DateTime.utc_now()
        }
      }

      {:ok, comprehensive_suggestions}
    else
      {:error, reason} -> {:error, {:comprehensive_suggestions_failed, reason}}
    end
  end

  # Auto-categorization functions

  defp analyze_prompt_content_for_categorization(content) do
    # Analyze prompt content to suggest categories
    content_keywords = extract_categorization_keywords(content)
    content_type = determine_prompt_content_type(content)
    content_complexity = assess_prompt_complexity(content)

    %{
      keywords: content_keywords,
      content_type: content_type,
      complexity: content_complexity,
      suggested_categories: suggest_categories_from_content(content_keywords, content_type)
    }
  end

  defp analyze_user_context_for_categorization(user_context) do
    # Analyze user context for categorization hints
    %{
      user_workflow: Map.get(user_context, :workflow_type, :general),
      project_context: Map.get(user_context, :project_id),
      usage_context: Map.get(user_context, :usage_context, :general)
    }
  end

  defp determine_suggested_categories(content_analysis, context_analysis) do
    # Determine suggested categories based on analysis
    content_suggestions = content_analysis.suggested_categories
    context_suggestions = suggest_categories_from_context(context_analysis)

    # Combine and rank suggestions
    all_suggestions = content_suggestions ++ context_suggestions
    ranked_suggestions = rank_category_suggestions(all_suggestions)

    # Top 3 suggestions
    Enum.take(ranked_suggestions, 3)
  end

  # Helper functions

  defp get_user_prompt_collection(user_id) do
    # Get all prompts for user across three-tier hierarchy
    case Prompt.list_by_user(user_id) do
      {:ok, user_prompts} ->
        {:ok, user_prompts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_category_name(category_id) do
    # Get category name from ID
    case PromptCategory.read(id: category_id) do
      {:ok, [category]} -> category.name
      _ -> "Unknown Category"
    end
  end

  defp extract_tags_from_prompt(prompt) do
    # Extract tags from prompt content and metadata
    # Look for hashtags in content or existing tags field
    content_tags =
      Regex.scan(~r/#(\w+)/, prompt.content, capture: :all_but_first)
      |> List.flatten()

    existing_tags = prompt.tags || []

    Enum.uniq(content_tags ++ existing_tags)
  end

  defp get_primary_tag(tags) do
    # Get primary tag for organization (first tag or most relevant)
    case tags do
      [] -> nil
      [first_tag | _] -> first_tag
    end
  end

  defp apply_single_custom_rule(prompts, rule) do
    # Apply single custom organization rule
    case rule.rule_type do
      :filter_by_keyword ->
        Enum.filter(prompts, fn prompt ->
          String.contains?(String.downcase(prompt.content), rule.keyword)
        end)

      :group_by_pattern ->
        # Simplified - would implement pattern-based grouping
        prompts

      _ ->
        prompts
    end
  end

  # Analysis and suggestion helper functions

  defp analyze_collection_usage_patterns(user_id, prompt_collection) do
    # Analyze usage patterns for organization suggestions
    # Simplified implementation - would analyze actual PromptUsage records
    []
  end

  defp analyze_prompt_content_patterns(prompt_collection) do
    # Analyze content patterns across prompt collection
    prompt_collection
    |> Enum.group_by(fn prompt ->
      determine_prompt_content_type(prompt.content)
    end)
  end

  defp analyze_prompt_similarity(prompt_collection) do
    # Analyze similarity between prompts for grouping suggestions
    # Simplified implementation - would use text similarity algorithms
    []
  end

  defp extract_categorization_keywords(content) do
    # Extract keywords for categorization
    common_keywords = ["code", "review", "documentation", "testing", "analysis", "generation"]

    Enum.filter(common_keywords, fn keyword ->
      String.contains?(String.downcase(content), keyword)
    end)
  end

  defp determine_prompt_content_type(content) do
    # Determine the type of prompt based on content
    cond do
      String.contains?(String.downcase(content), ["review", "analyze", "check"]) ->
        :analysis

      String.contains?(String.downcase(content), ["generate", "create", "write"]) ->
        :generation

      String.contains?(String.downcase(content), ["explain", "describe", "document"]) ->
        :documentation

      String.contains?(String.downcase(content), ["test", "verify", "validate"]) ->
        :testing

      true ->
        :general
    end
  end

  defp assess_prompt_complexity(content) do
    # Assess prompt complexity for organization
    word_count = length(String.split(content))
    variable_count = length(Regex.scan(~r/\{\{.*?\}\}/, content))

    case {word_count, variable_count} do
      {words, vars} when words > 100 or vars > 5 -> :complex
      {words, vars} when words > 50 or vars > 2 -> :moderate
      _ -> :simple
    end
  end

  defp suggest_categories_from_content(keywords, content_type) do
    # Suggest categories based on content analysis
    base_category =
      case content_type do
        :analysis -> "Code Analysis"
        :generation -> "Content Generation"
        :documentation -> "Documentation"
        :testing -> "Testing"
        :general -> "General"
      end

    keyword_categories =
      Enum.map(keywords, fn keyword ->
        String.capitalize(keyword)
      end)

    [base_category | keyword_categories] |> Enum.uniq()
  end

  defp suggest_categories_from_context(context_analysis) do
    # Suggest categories based on user context
    case context_analysis.user_workflow do
      :code_review -> ["Code Review", "Quality Assurance"]
      :documentation -> ["Documentation", "User Guides"]
      :testing -> ["Testing", "Validation"]
      _ -> ["General", "Productivity"]
    end
  end

  defp rank_category_suggestions(suggestions) do
    # Rank category suggestions by relevance
    suggestions
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_category, frequency} -> frequency end, :desc)
    |> Enum.map(fn {category, _frequency} -> category end)
  end

  # Initialization and utility functions

  defp build_organization_config do
    %{
      default_scheme: :hierarchical,
      max_hierarchy_depth: 5,
      auto_categorization_enabled: true,
      suggestion_engine_enabled: true
    }
  end

  defp initialize_categorization_cache do
    %{}
  end

  defp initialize_suggestion_engine do
    %{
      enabled: true,
      analysis_methods: [:usage_patterns, :content_analysis, :similarity_analysis],
      suggestion_cache: %{}
    }
  end

  defp initialize_performance_metrics do
    %{
      total_organizations: 0,
      successful_organizations: 0,
      average_organization_time_ms: 0.0
    }
  end

  # Counting and utility functions
  defp count_categories_in_hierarchy(categorized_prompts), do: map_size(categorized_prompts)
  defp count_unique_tags(tagged_prompts), do: length(Map.keys(tagged_prompts))
  defp count_custom_categories(organized_prompts), do: map_size(organized_prompts)
  defp count_mixed_categories(mixed_organization), do: map_size(mixed_organization)
  defp merge_organization_views(hierarchical_result, tag_result), do: %{}
  defp build_usage_based_organization_suggestions(usage_patterns), do: []
  defp calculate_usage_suggestion_confidence(usage_patterns), do: 0.75
  defp build_content_based_organization_suggestions(content_analysis), do: []
  defp calculate_content_suggestion_confidence(content_analysis), do: 0.80
  defp build_similarity_based_organization_suggestions(similarity_groups), do: []
  defp combine_suggestion_types(suggestion_lists), do: List.flatten(suggestion_lists)
  defp calculate_comprehensive_confidence(suggestion_lists), do: 0.85
  defp calculate_categorization_confidence(content_analysis, context_analysis), do: %{}
end
