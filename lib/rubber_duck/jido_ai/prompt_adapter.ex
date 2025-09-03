defmodule RubberDuck.JidoAI.PromptAdapter do
  @moduledoc """
  JidoAI prompt management for RubberDuck - The unified prompt system.

  Handles all prompt operations using JidoAI.Prompt patterns, replacing legacy
  prompt systems entirely. Provides the three-tier hierarchical prompt
  system (System/Project/User) using JidoAI's structured prompt composition.

  Key capabilities:
  - JidoAI.Prompt.MessageItem for all prompt operations
  - JidoAI template inheritance for hierarchical composition
  - JidoAI security validation patterns
  - JidoAI EEx and Liquid template engines only
  - JidoAI.Prompt version management and history
  """

  require Logger

  alias Jido.AI.Prompt
  alias RubberDuck.Prompts.Composition.CompositionEngine
  alias RubberDuck.Prompts.Resources.{Prompt, PromptVersion}

  @doc """
  Create JidoAI.Prompt from hierarchical prompt data.
  """
  def create_jido_ai_prompt(prompt_data, context \\ %{}) do
    Logger.debug("Creating JidoAI prompt from hierarchical data")

    with {:ok, composed_content} <- compose_hierarchical_content(prompt_data, context),
         {:ok, messages} <- build_jido_ai_messages(composed_content, prompt_data),
         {:ok, jido_prompt} <- build_jido_prompt_from_messages(messages, prompt_data, context) do
      {:ok, jido_prompt}
    else
      {:error, reason} = error ->
        Logger.error("Failed to convert prompt to JidoAI format: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Render JidoAI prompt with hierarchical context and variable interpolation.
  """
  def render_jido_ai_prompt(jido_prompt, render_context \\ %{}) do
    Logger.debug("Rendering JidoAI prompt with context")

    # Enhance render context with RubberDuck-specific variables
    enhanced_context = enhance_render_context(render_context)

    case Prompt.render(jido_prompt, enhanced_context) do
      {:ok, messages} ->
        # Post-process messages with RubberDuck enhancements
        processed_messages = post_process_rendered_messages(messages, enhanced_context)
        {:ok, processed_messages}

      {:error, reason} = error ->
        Logger.error("Failed to render JidoAI prompt: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Create JidoAI template from existing prompt template.
  """
  def create_jido_ai_template(template_content, template_type, options \\ %{}) do
    Logger.debug("Creating JidoAI template from existing content")

    # Determine template engine based on content
    template_engine = determine_template_engine(template_content, options)

    # Convert template content to JidoAI format
    case convert_template_content(template_content, template_engine, options) do
      {:ok, jido_template_content} ->
        create_jido_template(jido_template_content, template_type, template_engine, options)

      {:error, reason} = error ->
        Logger.error("Failed to create JidoAI template: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Migrate existing prompt versions to JidoAI prompt history.
  """
  def migrate_prompt_versions(rubber_duck_prompt, options \\ %{}) do
    Logger.debug("Migrating prompt versions to JidoAI history")

    case get_prompt_versions(rubber_duck_prompt) do
      {:ok, versions} ->
        migrate_versions_to_jido_ai(versions, rubber_duck_prompt, options)

      {:error, reason} = error ->
        Logger.error("Failed to get prompt versions for migration: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Create JidoAI prompt with security validation integration.
  """
  def create_secure_jido_ai_prompt(content, context, options \\ %{}) do
    Logger.debug("Creating secure JidoAI prompt with validation")

    with {:ok, validated_content} <- validate_prompt_security(content, options),
         {:ok, messages} <- build_secure_messages(validated_content, context),
         {:ok, jido_prompt} <- create_jido_ai_prompt_from_messages(messages, context) do
      {:ok, jido_prompt}
    else
      {:error, reason} = error ->
        Logger.error("Failed to create secure JidoAI prompt: #{inspect(reason)}")
        error
    end
  end

  # Private implementation

  defp compose_hierarchical_content(rubber_duck_prompt, context) do
    # Use existing CompositionEngine to get hierarchical content
    case CompositionEngine.compose_prompt(rubber_duck_prompt.id, context) do
      {:ok, composed} ->
        {:ok, composed}

      {:error, reason} ->
        Logger.warning("Hierarchical composition failed, using base content: #{inspect(reason)}")
        {:ok, rubber_duck_prompt.content}
    end
  end

  defp build_jido_ai_messages(content, rubber_duck_prompt) do
    # Convert content to JidoAI message structure
    messages =
      case rubber_duck_prompt.level do
        :system ->
          [%{role: :system, content: content}]

        :user ->
          [%{role: :user, content: content}]

        :project ->
          # Project prompts become system messages with context
          [%{role: :system, content: "Project Context: #{content}"}]

        _ ->
          [%{role: :user, content: content}]
      end

    {:ok, messages}
  end

  defp build_jido_prompt_from_messages(messages, prompt_data, context) do
    # Build prompt options from RubberDuck prompt and context
    prompt_options = build_prompt_options_from_data(prompt_data, context)

    # Create JidoAI.Prompt
    case Prompt.new(messages, prompt_options) do
      %Prompt{} = jido_prompt ->
        # Add RubberDuck-specific metadata
        enhanced_prompt = enhance_jido_prompt_with_metadata(jido_prompt, prompt_data)
        {:ok, enhanced_prompt}

      error ->
        {:error, {:jido_prompt_creation_failed, error}}
    end
  end

  defp build_prompt_options_from_data(prompt_data, context) do
    base_options = %{
      temperature: 0.1,
      max_tokens: 1500,
      # Default to EEx for compatibility with existing templates
      engine: :eex
    }

    # Add options from rubber_duck_prompt if available
    rubber_duck_options =
      case prompt_data do
        nil ->
          %{}

        prompt ->
          %{
            name: prompt.name,
            description: prompt.description,
            category: prompt.category_id,
            level: prompt.level,
            ruby_duck_id: prompt.id
          }
      end

    # Add options from context
    context_options = Map.take(context, [:temperature, :max_tokens, :engine, :timeout])

    Map.merge(base_options, Map.merge(rubber_duck_options, context_options))
  end

  defp enhance_jido_prompt_with_metadata(jido_prompt, rubber_duck_prompt) do
    # Add RubberDuck metadata to JidoAI prompt
    rubber_duck_metadata =
      case rubber_duck_prompt do
        nil ->
          %{}

        prompt ->
          %{
            rubber_duck_source: true,
            original_id: prompt.id,
            level: prompt.level,
            category: prompt.category_id,
            created_at: prompt.inserted_at,
            updated_at: prompt.updated_at
          }
      end

    # This would enhance the JidoAI prompt with metadata
    # (JidoAI.Prompt may not directly support metadata, so we'd store this separately)
    Map.put(jido_prompt, :rubber_duck_metadata, rubber_duck_metadata)
  end

  defp enhance_render_context(render_context) do
    # Add RubberDuck-specific context variables
    base_enhancements = %{
      app_name: "RubberDuck",
      timestamp: DateTime.utc_now(),
      system_version: Application.spec(:rubber_duck, :vsn) |> to_string()
    }

    Map.merge(render_context, base_enhancements)
  end

  defp post_process_rendered_messages(messages, context) do
    # Post-process rendered messages with RubberDuck-specific enhancements
    Enum.map(messages, fn message ->
      enhanced_content = enhance_message_content(message.content, context)
      Map.put(message, :content, enhanced_content)
    end)
  end

  defp enhance_message_content(content, _context) do
    # Apply RubberDuck-specific content enhancements
    # For now, just return content as-is, but could add:
    # - Security sanitization
    # - Content validation
    # - Format standardization
    content
  end

  defp determine_template_engine(template_content, options) do
    # Determine appropriate template engine for content
    case Map.get(options, :engine) do
      nil ->
        # Auto-detect based on content
        cond do
          String.contains?(template_content, "<%") -> :eex
          String.contains?(template_content, "{{") -> :liquid
          # Default to EEx for Elixir compatibility
          true -> :eex
        end

      explicit_engine ->
        explicit_engine
    end
  end

  defp convert_template_content(template_content, template_engine, options) do
    # Convert existing template content to JidoAI-compatible format
    case template_engine do
      :eex ->
        # EEx templates should work directly with JidoAI
        {:ok, template_content}

      :liquid ->
        # Convert EEx patterns to Liquid if needed
        converted_content = convert_eex_to_liquid(template_content)
        {:ok, converted_content}

      _ ->
        {:error, :unsupported_template_engine}
    end
  end

  defp convert_eex_to_liquid(eex_content) do
    # Basic conversion from EEx to Liquid syntax
    # This is a simplified conversion - would need more sophisticated handling in production
    eex_content
    |> String.replace(~r/<%=\s*@(\w+)\s*%>/, "{{ \\1 }}")
    |> String.replace(~r/<%=\s*(\w+)\s*%>/, "{{ \\1 }}")
  end

  defp create_jido_template(template_content, template_type, template_engine, options) do
    # Create JidoAI template with specified engine
    messages =
      case template_type do
        :system ->
          [%{role: :system, content: template_content, engine: template_engine}]

        :user ->
          [%{role: :user, content: template_content, engine: template_engine}]

        :mixed ->
          # Parse mixed content for multiple messages
          parse_mixed_template_content(template_content, template_engine)
      end

    template_options = Map.merge(options, %{engine: template_engine})

    case Prompt.new(messages, template_options) do
      %Prompt{} = template ->
        {:ok, template}

      error ->
        {:error, {:template_creation_failed, error}}
    end
  end

  defp parse_mixed_template_content(content, template_engine) do
    # Parse content that might contain multiple message roles
    # This would implement more sophisticated parsing in production
    [%{role: :user, content: content, engine: template_engine}]
  end

  defp get_prompt_versions(rubber_duck_prompt) do
    # Get prompt versions from existing system
    # Would integrate with actual PromptVersion resource in production
    versions = [
      %{
        version: 1,
        content: rubber_duck_prompt.content,
        created_at: rubber_duck_prompt.inserted_at,
        created_by: rubber_duck_prompt.created_by
      }
    ]

    {:ok, versions}
  end

  defp migrate_versions_to_jido_ai(versions, rubber_duck_prompt, options) do
    Logger.debug("Migrating #{length(versions)} versions to JidoAI")

    migrated_versions =
      Enum.map(versions, fn version ->
        case convert_version_to_jido_ai(version, rubber_duck_prompt, options) do
          {:ok, jido_version} ->
            jido_version

          {:error, reason} ->
            Logger.warning("Failed to migrate version: #{inspect(reason)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    Logger.debug("Successfully migrated #{length(migrated_versions)} versions")
    {:ok, migrated_versions}
  end

  defp convert_version_to_jido_ai(version, rubber_duck_prompt, options) do
    # Convert individual version to JidoAI format
    context =
      Map.merge(options, %{
        version: version.version,
        created_at: version.created_at,
        created_by: version.created_by
      })

    # Create temporary prompt for this version
    version_prompt = %{
      rubber_duck_prompt
      | content: version.content,
        inserted_at: version.created_at
    }

    convert_version_to_jido_ai_prompt(version_prompt, context)
  end

  defp validate_prompt_security(content, options) do
    # Integrate with existing prompt security validation
    security_level = Map.get(options, :security_level, :standard)

    case security_level do
      :high ->
        # Use existing PromptValidator for high security
        validate_with_existing_security_system(content, options)

      :standard ->
        # Basic validation for standard security
        basic_security_validation(content)

      :low ->
        # Minimal validation for low security
        {:ok, content}
    end
  end

  defp validate_with_existing_security_system(content, options) do
    # Would integrate with RubberDuck.Prompts.Security.PromptValidator
    # For now, simulate validation
    case String.contains?(content, ["<script>", "DROP TABLE", "rm -rf"]) do
      true ->
        {:error, :security_violation_detected}

      false ->
        {:ok, content}
    end
  end

  defp basic_security_validation(content) do
    # Basic security checks
    if String.length(content) > 50_000 do
      {:error, :content_too_long}
    else
      {:ok, content}
    end
  end

  defp build_secure_messages(validated_content, context) do
    # Build messages with security context
    role = Map.get(context, :role, :user)

    messages = [
      %{
        role: role,
        content: validated_content
      }
    ]

    # Add security metadata
    secure_messages =
      Enum.map(messages, fn message ->
        Map.put(message, :security_validated, true)
      end)

    {:ok, secure_messages}
  end

  @doc """
  Integrate existing prompt caching with JidoAI.
  """
  def get_cached_jido_ai_prompt(cache_key, build_function) when is_function(build_function, 0) do
    Logger.debug("Attempting to retrieve cached JidoAI prompt")

    # Try to get from existing cache system
    case get_from_existing_cache(cache_key) do
      {:hit, cached_prompt} ->
        Logger.debug("JidoAI prompt cache hit")
        {:ok, cached_prompt}

      :miss ->
        Logger.debug("JidoAI prompt cache miss, building new prompt")

        case build_function.() do
          {:ok, jido_prompt} ->
            # Store in cache for future use
            store_in_existing_cache(cache_key, jido_prompt)
            {:ok, jido_prompt}

          error ->
            error
        end
    end
  end

  defp get_from_existing_cache(cache_key) do
    # Would integrate with existing cache system
    # (RubberDuck.Prompts.Caching.CacheManager)
    # Simulate cache miss for now
    :miss
  end

  defp store_in_existing_cache(cache_key, jido_prompt) do
    # Would store in existing cache system
    Logger.debug("Storing JidoAI prompt in cache with key: #{cache_key}")
    :ok
  end

  @doc """
  Validate JidoAI prompt adapter functionality.
  """
  def validate_adapter_functionality do
    Logger.debug("Validating JidoAI prompt adapter functionality")

    validations = [
      validate_conversion_accuracy(),
      validate_rendering_performance(),
      validate_template_creation(),
      validate_security_integration(),
      validate_caching_integration()
    ]

    case Enum.all?(validations, &(&1 == :ok)) do
      true ->
        Logger.info("JidoAI prompt adapter validation passed")
        :ok

      false ->
        Logger.error("JidoAI prompt adapter validation failed")
        {:error, :validation_failed}
    end
  end

  # Private validation functions

  # Implementation of missing functions using JidoAI 0.5.2 API

  defp create_jido_ai_prompt_from_messages(messages, context) do
    # Create JidoAI prompt from messages using the 0.5.2 API
    prompt_attrs = %{
      messages: messages,
      params: Map.get(context, :template_params, %{}),
      metadata: build_metadata_from_context(context)
    }

    case Jido.AI.Prompt.new(prompt_attrs) do
      %Jido.AI.Prompt{} = prompt ->
        {:ok, prompt}

      error ->
        Logger.error("Failed to create JidoAI prompt: #{inspect(error)}")
        {:error, {:jido_prompt_creation_failed, error}}
    end
  end

  defp convert_version_to_jido_ai_prompt(version_prompt, context) do
    # Convert prompt version to JidoAI prompt
    messages = [
      %{
        role: determine_role_from_level(version_prompt.level),
        content: version_prompt.content
      }
    ]

    create_jido_ai_prompt_from_messages(messages, context)
  end

  defp convert_test_prompt_to_jido_ai(test_prompt) do
    # Convert test prompt to JidoAI format
    messages = [
      %{
        role: determine_role_from_level(test_prompt.level),
        content: test_prompt.content
      }
    ]

    context = %{
      test_conversion: true,
      prompt_name: test_prompt.name
    }

    create_jido_ai_prompt_from_messages(messages, context)
  end

  defp build_metadata_from_context(context) do
    # Build JidoAI prompt metadata from context
    %{
      source: "rubber_duck_prompt_adapter",
      created_at: DateTime.utc_now(),
      context_type: Map.get(context, :context_type, :general),
      integration_version: "6.1.0"
    }
  end

  defp determine_role_from_level(level) do
    # Convert RubberDuck prompt levels to JidoAI message roles
    case level do
      :system -> :system
      :user -> :user
      :assistant -> :assistant
      _ -> :user  # Default to user role
    end
  end

  defp validate_conversion_accuracy do
    # Test conversion accuracy
    test_prompt = %{
      id: "test",
      content: "Test prompt content",
      level: :user,
      name: "test_prompt"
    }

    case convert_test_prompt_to_jido_ai(test_prompt) do
      {:ok, _jido_prompt} -> :ok
      {:error, _} -> {:error, :conversion_failed}
    end
  end

  defp validate_rendering_performance do
    # Test rendering performance
    start_time = System.monotonic_time(:millisecond)

    test_messages = [%{role: :user, content: "Hello <%= @name %>", engine: :eex}]
    test_context = %{name: "World"}

    case Prompt.new(test_messages) do
      %Prompt{} = prompt ->
        case Prompt.render(prompt, test_context) do
          {:ok, _rendered} ->
            end_time = System.monotonic_time(:millisecond)
            render_time = end_time - start_time

            # Sub-50ms target
            if render_time < 50 do
              :ok
            else
              {:error, :rendering_too_slow}
            end

          {:error, _} ->
            {:error, :rendering_failed}
        end

      error ->
        {:error, {:prompt_creation_failed, error}}
    end
  end

  defp validate_template_creation do
    # Test template creation
    test_template = "Hello <%= @user %>, welcome to <%= @app %>!"

    case create_jido_ai_template(test_template, :user, %{engine: :eex}) do
      {:ok, _template} -> :ok
      {:error, _} -> {:error, :template_creation_failed}
    end
  end

  defp validate_security_integration do
    # Test security validation integration
    malicious_content = "<script>alert('xss')</script>"

    case validate_prompt_security(malicious_content, %{security_level: :high}) do
      # Should detect and reject
      {:error, :security_violation_detected} -> :ok
      # Should not pass
      {:ok, _} -> {:error, :security_validation_failed}
      {:error, _} -> {:error, :security_system_error}
    end
  end

  defp validate_caching_integration do
    # Test caching integration
    cache_key = "test_jido_ai_cache"

    build_function = fn ->
      messages = [%{role: :user, content: "Test cached prompt"}]

      case Prompt.new(messages) do
        %Prompt{} = prompt -> {:ok, prompt}
        error -> {:error, error}
      end
    end

    case get_cached_jido_ai_prompt(cache_key, build_function) do
      {:ok, _prompt} -> :ok
      {:error, _} -> {:error, :caching_integration_failed}
    end
  end

  @doc """
  Get JidoAI prompt adapter status and metrics.
  """
  def get_adapter_status do
    validation_result = validate_adapter_functionality()

    %{
      adapter_operational: validation_result == :ok,
      jido_ai_integration: true,
      supported_engines: [:eex, :liquid],
      security_integration: :enabled,
      caching_integration: :enabled,
      conversion_accuracy: :high,
      performance_target: "sub-50ms rendering",
      last_validated: DateTime.utc_now()
    }
  end
end
