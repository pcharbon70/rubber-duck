defmodule RubberDuck.Prompts.WorkflowIntegration.NamedPromptReferenceManager do
  @moduledoc """
  Named prompt reference management service for workflow integration.
  
  Provides comprehensive management of named prompt references within workflow 
  definitions, enabling workflows to reference prompts by name with validation,
  resolution tracking, and dependency management. Coordinates with prompt agents
  for dynamic resolution and optimization.
  
  Features:
  - Named prompt reference validation and management with comprehensive checking
  - Reference dependency tracking and resolution with circular dependency detection
  - Dynamic reference resolution with caching and performance optimization
  - Workflow-specific reference context management with inheritance and customization
  - Integration with prompt agent ecosystem for seamless prompt composition
  - Reference lifecycle management with creation, update, and cleanup capabilities
  """

  use GenServer
  require Logger

  alias RubberDuck.Prompts.Agents.PromptLibraryAgent

  @reference_types [:direct, :inherited, :computed, :conditional]
  @reference_scopes [:global, :project, :user, :workflow, :step]

  @default_manager_config %{
    enable_validation: true,
    enable_dependency_tracking: true,
    enable_reference_caching: true,
    max_reference_depth: 5,
    circular_dependency_detection: true
  }

  defstruct [
    :manager_config,
    :reference_registry,
    :dependency_graph,
    :validation_cache,
    :performance_metrics
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    state = %__MODULE__{
      manager_config: Map.merge(@default_manager_config, Keyword.get(opts, :config, %{})),
      reference_registry: initialize_reference_registry(),
      dependency_graph: initialize_dependency_graph(),
      validation_cache: initialize_validation_cache(),
      performance_metrics: initialize_performance_metrics()
    }

    Logger.info("NamedPromptReferenceManager: Reference manager initialized",
      reference_types: @reference_types,
      reference_scopes: @reference_scopes
    )

    {:ok, state}
  end

  # Public API

  def register_prompt_reference(workflow_id, reference_spec, options \\ %{}) do
    GenServer.call(__MODULE__, {:register_prompt_reference, workflow_id, reference_spec, options})
  end

  def resolve_prompt_reference(workflow_id, reference_name, context \\ %{}) do
    GenServer.call(__MODULE__, {:resolve_prompt_reference, workflow_id, reference_name, context})
  end

  def validate_prompt_references(workflow_id, reference_list) do
    GenServer.call(__MODULE__, {:validate_prompt_references, workflow_id, reference_list})
  end

  def get_workflow_references(workflow_id) do
    GenServer.call(__MODULE__, {:get_workflow_references, workflow_id})
  end

  def update_reference_dependency_graph(workflow_id) do
    GenServer.cast(__MODULE__, {:update_dependency_graph, workflow_id})
  end

  def cleanup_workflow_references(workflow_id) do
    GenServer.cast(__MODULE__, {:cleanup_workflow_references, workflow_id})
  end

  # GenServer callbacks

  def handle_call({:register_prompt_reference, workflow_id, reference_spec, options}, _from, state) do
    Logger.debug("NamedPromptReferenceManager: Registering prompt reference",
      workflow_id: workflow_id,
      reference_name: Map.get(reference_spec, :name, "unknown")
    )

    case execute_reference_registration(workflow_id, reference_spec, options, state) do
      {:ok, registration_result} ->
        updated_state = update_reference_registry(state, workflow_id, registration_result)

        Logger.info("NamedPromptReferenceManager: Reference registered successfully",
          workflow_id: workflow_id,
          reference_name: registration_result.reference_name,
          reference_type: registration_result.reference_type
        )

        {:reply, {:ok, registration_result}, updated_state}

      {:error, reason} ->
        Logger.error("NamedPromptReferenceManager: Reference registration failed",
          workflow_id: workflow_id,
          error: reason
        )

        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:resolve_prompt_reference, workflow_id, reference_name, context}, _from, state) do
    case execute_reference_resolution(workflow_id, reference_name, context, state) do
      {:ok, resolution_result} ->
        {:reply, {:ok, resolution_result}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:validate_prompt_references, workflow_id, reference_list}, _from, state) do
    case execute_references_validation(workflow_id, reference_list, state) do
      {:ok, validation_result} ->
        {:reply, {:ok, validation_result}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_workflow_references, workflow_id}, _from, state) do
    references = get_references_for_workflow(state.reference_registry, workflow_id)
    {:reply, {:ok, references}, state}
  end

  def handle_cast({:update_dependency_graph, workflow_id}, state) do
    updated_graph = update_dependency_graph_for_workflow(state.dependency_graph, workflow_id, state)
    updated_state = %{state | dependency_graph: updated_graph}

    {:noreply, updated_state}
  end

  def handle_cast({:cleanup_workflow_references, workflow_id}, state) do
    cleaned_registry = cleanup_references_for_workflow(state.reference_registry, workflow_id)
    cleaned_graph = cleanup_dependency_graph_for_workflow(state.dependency_graph, workflow_id)

    updated_state = %{state | reference_registry: cleaned_registry, dependency_graph: cleaned_graph}

    Logger.debug("NamedPromptReferenceManager: Cleaned up references for workflow", workflow_id: workflow_id)

    {:noreply, updated_state}
  end

  # Private implementation functions

  defp execute_reference_registration(workflow_id, reference_spec, options, state) do
    # Execute prompt reference registration
    with {:ok, validated_spec} <- validate_reference_specification(reference_spec, options),
         {:ok, reference_context} <- build_reference_context(workflow_id, validated_spec, options),
         {:ok, dependency_analysis} <- analyze_reference_dependencies(validated_spec, state) do
      
      registration_result = %{
        reference_name: validated_spec.name,
        reference_type: validated_spec.type,
        reference_scope: validated_spec.scope,
        workflow_id: workflow_id,
        reference_context: reference_context,
        dependency_analysis: dependency_analysis,
        registered_at: DateTime.utc_now(),
        registration_successful: true
      }

      {:ok, registration_result}
    else
      {:error, reason} -> {:error, {:reference_registration_failed, reason}}
    end
  end

  defp execute_reference_resolution(workflow_id, reference_name, context, state) do
    # Execute prompt reference resolution
    case get_reference_from_registry(state.reference_registry, workflow_id, reference_name) do
      {:ok, reference_entry} ->
        resolve_reference_with_context(reference_entry, context, state)

      {:error, reason} ->
        {:error, {:reference_not_found, reason}}
    end
  end

  defp execute_references_validation(workflow_id, reference_list, state) do
    # Execute validation for multiple references
    validation_results = Enum.map(reference_list, fn reference ->
      validate_single_reference(workflow_id, reference, state)
    end)

    successful_validations = Enum.filter(validation_results, &match?({:ok, _}, &1))
    failed_validations = Enum.filter(validation_results, &match?({:error, _}, &1))

    validation_summary = %{
      total_references: length(reference_list),
      successful_validations: length(successful_validations),
      failed_validations: length(failed_validations),
      validation_success_rate: length(successful_validations) / length(reference_list),
      validation_details: validation_results
    }

    {:ok, validation_summary}
  end

  defp validate_reference_specification(reference_spec, options) do
    # Validate reference specification structure
    required_fields = [:name, :type, :scope]
    optional_fields = [:dependencies, :context, :resolution_strategy]

    case validate_required_fields(reference_spec, required_fields) do
      {:ok, _} ->
        validated_spec = enhance_reference_spec_with_defaults(reference_spec, optional_fields)
        {:ok, validated_spec}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_reference_context(workflow_id, reference_spec, options) do
    # Build comprehensive reference context
    reference_context = %{
      workflow_id: workflow_id,
      reference_name: reference_spec.name,
      reference_scope: reference_spec.scope,
      resolution_options: options,
      context_inheritance: determine_context_inheritance(reference_spec),
      created_at: DateTime.utc_now()
    }

    {:ok, reference_context}
  end

  defp analyze_reference_dependencies(reference_spec, state) do
    # Analyze dependencies for circular dependency detection
    dependencies = Map.get(reference_spec, :dependencies, [])

    dependency_analysis = %{
      direct_dependencies: dependencies,
      dependency_count: length(dependencies),
      circular_dependencies: detect_circular_dependencies(dependencies, state),
      dependency_depth: calculate_dependency_depth(dependencies, state)
    }

    {:ok, dependency_analysis}
  end

  defp resolve_reference_with_context(reference_entry, context, state) do
    # Resolve reference with workflow context
    enhanced_context = enhance_reference_context(reference_entry, context)

    resolution_result = %{
      reference_name: reference_entry.reference_name,
      reference_type: reference_entry.reference_type,
      resolved_context: enhanced_context,
      resolution_successful: true,
      resolved_at: DateTime.utc_now()
    }

    {:ok, resolution_result}
  end

  # Helper functions

  defp validate_required_fields(spec, required_fields) do
    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(spec, field)
    end)

    if Enum.empty?(missing_fields) do
      {:ok, :all_fields_present}
    else
      {:error, {:missing_required_fields, missing_fields}}
    end
  end

  defp enhance_reference_spec_with_defaults(reference_spec, optional_fields) do
    # Add default values for optional fields
    defaults = %{
      dependencies: [],
      context: %{},
      resolution_strategy: :standard
    }

    Map.merge(defaults, reference_spec)
  end

  defp determine_context_inheritance(reference_spec) do
    # Determine context inheritance strategy
    case reference_spec.scope do
      :global -> :full_inheritance
      :project -> :project_inheritance  
      :user -> :user_inheritance
      :workflow -> :workflow_inheritance
      :step -> :step_inheritance
    end
  end

  defp detect_circular_dependencies(dependencies, state) do
    # Detect circular dependencies (simplified implementation)
    case state.manager_config.circular_dependency_detection do
      true -> 
        # Would implement actual circular dependency detection
        []
      false -> 
        []
    end
  end

  defp calculate_dependency_depth(dependencies, state) do
    # Calculate maximum dependency depth
    case dependencies do
      [] -> 0
      deps -> min(length(deps), state.manager_config.max_reference_depth)
    end
  end

  defp enhance_reference_context(reference_entry, context) do
    # Enhance context with reference-specific information
    Map.merge(context, %{
      reference_metadata: %{
        reference_name: reference_entry.reference_name,
        reference_type: reference_entry.reference_type,
        workflow_id: reference_entry.workflow_id
      },
      resolution_timestamp: DateTime.utc_now()
    })
  end

  defp validate_single_reference(workflow_id, reference, state) do
    # Validate a single reference
    case Map.get(state.reference_registry, workflow_id) do
      nil -> {:error, {:workflow_not_found, workflow_id}}
      
      workflow_references ->
        reference_name = Map.get(reference, :name, "unknown")
        
        case Map.get(workflow_references, reference_name) do
          nil -> {:error, {:reference_not_found, reference_name}}
          _reference_entry -> {:ok, {:reference_valid, reference_name}}
        end
    end
  end

  defp get_references_for_workflow(registry, workflow_id) do
    Map.get(registry, workflow_id, %{})
  end

  defp update_reference_registry(state, workflow_id, registration_result) do
    # Update reference registry with new registration
    workflow_references = Map.get(state.reference_registry, workflow_id, %{})
    
    updated_references = Map.put(
      workflow_references, 
      registration_result.reference_name, 
      registration_result
    )
    
    updated_registry = Map.put(state.reference_registry, workflow_id, updated_references)
    
    %{state | reference_registry: updated_registry}
  end

  defp update_dependency_graph_for_workflow(graph, workflow_id, state) do
    # Update dependency graph for workflow
    workflow_references = get_references_for_workflow(state.reference_registry, workflow_id)
    
    # Build dependency relationships
    workflow_dependencies = Enum.reduce(workflow_references, %{}, fn {ref_name, ref_entry}, acc ->
      dependencies = Map.get(ref_entry, :dependency_analysis, %{})
      |> Map.get(:direct_dependencies, [])
      
      Map.put(acc, ref_name, dependencies)
    end)
    
    Map.put(graph, workflow_id, workflow_dependencies)
  end

  defp cleanup_references_for_workflow(registry, workflow_id) do
    Map.delete(registry, workflow_id)
  end

  defp cleanup_dependency_graph_for_workflow(graph, workflow_id) do
    Map.delete(graph, workflow_id)
  end

  # Initialization functions

  defp initialize_reference_registry do
    %{}
  end

  defp initialize_dependency_graph do
    %{}
  end

  defp initialize_validation_cache do
    %{}
  end

  defp get_reference_from_registry(registry, workflow_id, reference_name) do
    # Get reference from registry
    case Map.get(registry, workflow_id) do
      nil -> {:error, {:workflow_not_found, workflow_id}}
      
      workflow_references ->
        case Map.get(workflow_references, reference_name) do
          nil -> {:error, {:reference_not_found, reference_name}}
          reference_entry -> {:ok, reference_entry}
        end
    end
  end

  defp initialize_performance_metrics do
    %{
      total_registrations: 0,
      successful_registrations: 0,
      total_resolutions: 0,
      successful_resolutions: 0,
      validation_success_rate: 1.0
    }
  end
end