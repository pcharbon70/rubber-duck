defmodule RubberDuck.Rag.Generation do
  @moduledoc """
  Core Generation struct for RAG pipeline processing with prompt composition integration.

  This module defines the central data structure used throughout the RAG pipeline
  to track query processing, embedding generation, retrieval results, context building,
  prompt construction, response generation, and quality evaluation.

  The Generation struct flows through each stage of the pipeline, accumulating
  data and metadata for comprehensive quality assessment and learning.

  Enhanced with Phase 02b Section 6.1 LLM Orchestration Integration:
  - Project-specific RAG query enhancement with prompt context injection
  - Context-aware prompt modification based on RAG results with semantic integration
  - RAG result injection into project prompts with content optimization
  - Performance optimization for RAG + prompt composition with caching coordination

  Pipeline Flow:
  Query → Embedding → Multi-Retrieval → Fusion → Context → Prompt Enhancement → Generation → Evaluation
  """

  alias RubberDuck.Prompts.Integrations.RagPromptEnhancer
  alias RubberDuck.Rag.{Embedding, Evaluation, Retrieval}

  @type retrieval_results :: %{
          semantic_results: [map()],
          fulltext_results: [map()],
          fused_results: [map()],
          fusion_metadata: map()
        }

  @type evaluation_results :: %{
          rag_triad: %{
            context_relevance_score: float(),
            groundedness_score: float(),
            answer_relevance_score: float()
          },
          hallucination_score: float(),
          quality_score: float(),
          confidence_score: float()
        }

  @type telemetry_metadata :: %{
          pipeline_start_time: integer(),
          stage_timings: map(),
          provider_usage: map(),
          resource_consumption: map(),
          error_tracking: [map()]
        }

  defstruct [
    # Input data
    query: nil,
    query_metadata: %{},

    # Embedding stage
    query_embedding: nil,
    embedding_metadata: %{},

    # Retrieval stage
    retrieval_results: %{
      semantic_results: [],
      fulltext_results: [],
      fused_results: [],
      fusion_metadata: %{}
    },

    # Context building stage
    context: nil,
    context_sources: [],
    context_metadata: %{},

    # Prompt building stage
    prompt: nil,
    prompt_metadata: %{},

    # Prompt enhancement stage (new integration)
    prompt_enhanced: false,
    prompt_enhancement_metadata: %{},
    rag_prompt_context: nil,

    # Generation stage
    response: nil,
    generation_metadata: %{},

    # Evaluation stage
    evaluations: %{
      rag_triad: %{
        context_relevance_score: nil,
        groundedness_score: nil,
        answer_relevance_score: nil
      },
      hallucination: nil,
      quality_metrics: %{}
    },

    # Pipeline control
    halted?: false,
    halt_reason: nil,
    errors: [],

    # Monitoring and learning
    telemetry_metadata: %{
      pipeline_start_time: nil,
      stage_timings: %{},
      provider_usage: %{},
      resource_consumption: %{},
      error_tracking: []
    },

    # Reference and context
    ref: nil,
    pipeline_config: %{},
    user_context: %{}
  ]

  @type t :: %__MODULE__{
          query: binary() | nil,
          query_metadata: map(),
          query_embedding: [float()] | nil,
          embedding_metadata: map(),
          retrieval_results: retrieval_results(),
          context: binary() | nil,
          context_sources: [binary()],
          context_metadata: map(),
          prompt: binary() | nil,
          prompt_metadata: map(),
          prompt_enhanced: boolean(),
          prompt_enhancement_metadata: map(),
          rag_prompt_context: binary() | nil,
          response: binary() | nil,
          generation_metadata: map(),
          evaluations: evaluation_results(),
          halted?: boolean(),
          halt_reason: atom() | nil,
          errors: [map()],
          telemetry_metadata: telemetry_metadata(),
          ref: reference() | nil,
          pipeline_config: map(),
          user_context: map()
        }

  @doc """
  Create a new Generation struct for RAG pipeline processing.
  """
  def new(query, opts \\ []) do
    %__MODULE__{
      query: query,
      query_metadata: Keyword.get(opts, :query_metadata, %{}),
      pipeline_config: Keyword.get(opts, :pipeline_config, %{}),
      user_context: Keyword.get(opts, :user_context, %{}),
      ref: make_ref(),
      telemetry_metadata: %{
        pipeline_start_time: System.monotonic_time(:microsecond),
        stage_timings: %{},
        provider_usage: %{},
        resource_consumption: %{},
        error_tracking: []
      }
    }
  end

  @doc """
  Add embedding data to the generation struct.
  """
  def put_embedding(generation, embedding, metadata \\ %{}) do
    %{
      generation
      | query_embedding: embedding,
        embedding_metadata: Map.merge(generation.embedding_metadata, metadata)
    }
    |> record_stage_timing(:embedding_generation)
  end

  @doc """
  Add retrieval results to the generation struct.
  """
  def put_retrieval_results(generation, results, metadata \\ %{}) do
    %{generation | retrieval_results: Map.merge(generation.retrieval_results, results)}
    |> update_in([:retrieval_results, :fusion_metadata], &Map.merge(&1, metadata))
    |> record_stage_timing(:retrieval)
  end

  @doc """
  Add context information to the generation struct.
  """
  def put_context(generation, context, sources, metadata \\ %{}) do
    %{
      generation
      | context: context,
        context_sources: sources,
        context_metadata: Map.merge(generation.context_metadata, metadata)
    }
    |> record_stage_timing(:context_building)
  end

  @doc """
  Add prompt information to the generation struct.
  """
  def put_prompt(generation, prompt, metadata \\ %{}) do
    %{
      generation
      | prompt: prompt,
        prompt_metadata: Map.merge(generation.prompt_metadata, metadata)
    }
    |> record_stage_timing(:prompt_building)
  end

  @doc """
  Enhance prompt with RAG integration using the prompt composition system.
  """
  def enhance_prompt_with_rag(generation, enhancement_options \\ %{}) do
    case generation.prompt do
      nil ->
        add_error(generation, %{
          error: "Cannot enhance prompt - no prompt available",
          type: :prompt_enhancement
        })

      prompt_content ->
        execute_prompt_enhancement(generation, prompt_content, enhancement_options)
    end
  end

  @doc """
  Add RAG-specific prompt context to the generation struct.
  """
  def put_rag_prompt_context(generation, rag_context, metadata \\ %{}) do
    %{
      generation
      | rag_prompt_context: rag_context,
        prompt_enhancement_metadata: Map.merge(generation.prompt_enhancement_metadata, metadata),
        prompt_enhanced: true
    }
    |> record_stage_timing(:prompt_enhancement)
  end

  @doc """
  Add response information to the generation struct.
  """
  def put_response(generation, response, metadata \\ %{}) do
    %{
      generation
      | response: response,
        generation_metadata: Map.merge(generation.generation_metadata, metadata)
    }
    |> record_stage_timing(:response_generation)
  end

  @doc """
  Add evaluation results to the generation struct.
  """
  def put_evaluation(generation, evaluation_results) do
    %{generation | evaluations: Map.merge(generation.evaluations, evaluation_results)}
    |> record_stage_timing(:evaluation)
  end

  @doc """
  Mark the generation as halted with a reason.
  """
  def halt(generation, reason) do
    %{generation | halted?: true, halt_reason: reason}
    |> record_stage_timing(:halted)
  end

  @doc """
  Add an error to the generation struct.
  """
  def add_error(generation, error) when is_map(error) do
    error_entry =
      Map.merge(error, %{
        timestamp: System.system_time(:second),
        stage: determine_current_stage(generation)
      })

    %{generation | errors: [error_entry | generation.errors]}
    |> update_in([:telemetry_metadata, :error_tracking], &[error_entry | &1])
  end

  def add_error(generation, error) when is_atom(error) or is_binary(error) do
    add_error(generation, %{error: error, type: :general})
  end

  @doc """
  Check if the generation has any errors.
  """
  def has_errors?(generation) do
    not Enum.empty?(generation.errors)
  end

  @doc """
  Get the current stage of the RAG pipeline based on completed data.
  """
  def current_stage(generation) do
    determine_current_stage(generation)
  end

  @doc """
  Calculate total pipeline processing time in microseconds.
  """
  def total_processing_time(generation) do
    start_time = generation.telemetry_metadata.pipeline_start_time

    if start_time do
      System.monotonic_time(:microsecond) - start_time
    else
      0
    end
  end

  @doc """
  Get stage-specific processing times.
  """
  def stage_timings(generation) do
    generation.telemetry_metadata.stage_timings
  end

  @doc """
  Calculate pipeline progress as a percentage (0.0 to 1.0).
  """
  def progress(generation) do
    stages = [
      :embedding_generation,
      :retrieval,
      :context_building,
      :prompt_building,
      :prompt_enhancement,
      :response_generation,
      :evaluation
    ]

    completed_stages =
      Enum.count(stages, &Map.has_key?(generation.telemetry_metadata.stage_timings, &1))

    completed_stages / length(stages)
  end

  @doc """
  Extract comprehensive metadata for learning and optimization.
  """
  def extract_metadata(generation) do
    %{
      pipeline_performance: %{
        total_time_us: total_processing_time(generation),
        stage_timings: stage_timings(generation),
        progress: progress(generation)
      },
      quality_metrics: generation.evaluations,
      provider_usage: generation.telemetry_metadata.provider_usage,
      resource_consumption: generation.telemetry_metadata.resource_consumption,
      error_summary: %{
        error_count: length(generation.errors),
        error_types: Enum.map(generation.errors, &Map.get(&1, :type)),
        has_errors: has_errors?(generation)
      },
      pipeline_config: generation.pipeline_config,
      context_summary: %{
        sources_count: length(generation.context_sources),
        context_length: if(generation.context, do: String.length(generation.context), else: 0),
        retrieval_count: length(generation.retrieval_results.fused_results)
      },
      prompt_enhancement_summary: %{
        prompt_enhanced: generation.prompt_enhanced,
        enhancement_metadata: generation.prompt_enhancement_metadata,
        rag_prompt_context_available: not is_nil(generation.rag_prompt_context)
      }
    }
  end

  # Private helper functions

  defp execute_prompt_enhancement(generation, prompt_content, enhancement_options) do
    # Prepare RAG query based on original query and context
    rag_query = build_rag_query_from_generation(generation)

    # Prepare context for prompt enhancement
    context = build_enhancement_context(generation, enhancement_options)

    # Execute enhancement via RagPromptEnhancer
    case RagPromptEnhancer.enhance_prompt_with_rag(
           prompt_content,
           rag_query,
           context,
           enhancement_options
         ) do
      {:ok, enhancement_result} ->
        # Update generation with enhanced prompt and metadata
        enhanced_generation =
          %{
            generation
            | prompt: enhancement_result.enhanced_content,
              rag_prompt_context: build_rag_context_summary(generation),
              prompt_enhanced: true,
              prompt_enhancement_metadata:
                Map.merge(generation.prompt_enhancement_metadata, %{
                  enhancement_successful: true,
                  rag_context_injected: enhancement_result.rag_context_injected,
                  enhancement_strategy:
                    Map.get(enhancement_result, :enhancement_strategy, :unknown),
                  original_prompt_length: String.length(prompt_content),
                  enhanced_prompt_length: String.length(enhancement_result.enhanced_content)
                })
          }
          |> record_stage_timing(:prompt_enhancement)

        enhanced_generation

      {:error, reason} ->
        generation
        |> add_error(%{error: reason, type: :prompt_enhancement})
        |> Map.put(
          :prompt_enhancement_metadata,
          Map.merge(generation.prompt_enhancement_metadata, %{
            enhancement_successful: false,
            enhancement_error: reason
          })
        )
    end
  end

  defp build_rag_query_from_generation(generation) do
    # Build a comprehensive RAG query from the generation data
    base_query = generation.query || ""

    # Enhance query with context if available
    enhanced_query =
      case generation.context do
        nil ->
          base_query

        context when is_binary(context) ->
          if String.length(context) > 0 do
            "#{base_query}\n\nRelevant context: #{String.slice(context, 0, 500)}"
          else
            base_query
          end

        _ ->
          base_query
      end

    enhanced_query
  end

  defp build_enhancement_context(generation, enhancement_options) do
    # Build context map for prompt enhancement
    %{
      user_context: generation.user_context,
      pipeline_config: generation.pipeline_config,
      query_metadata: generation.query_metadata,
      retrieval_results_summary: summarize_retrieval_results(generation.retrieval_results),
      context_sources_count: length(generation.context_sources),
      enhancement_level: Map.get(enhancement_options, :enhancement_level, :standard),
      project_specific: Map.get(enhancement_options, :project_specific, true)
    }
  end

  defp build_rag_context_summary(generation) do
    # Build a summary of RAG context for injection
    context_parts = []

    # Add retrieval summary if available
    context_parts =
      if Enum.empty?(generation.retrieval_results.fused_results) do
        context_parts
      else
        retrieval_summary =
          "Retrieved #{length(generation.retrieval_results.fused_results)} relevant documents"

        [retrieval_summary | context_parts]
      end

    # Add context summary if available
    context_parts =
      if generation.context do
        context_summary =
          "Context includes #{String.length(generation.context)} characters from #{length(generation.context_sources)} sources"

        [context_summary | context_parts]
      else
        context_parts
      end

    case context_parts do
      [] -> "No RAG context available"
      parts -> Enum.join(parts, ". ")
    end
  end

  defp summarize_retrieval_results(retrieval_results) do
    %{
      semantic_results_count: length(retrieval_results.semantic_results),
      fulltext_results_count: length(retrieval_results.fulltext_results),
      fused_results_count: length(retrieval_results.fused_results),
      has_fusion_metadata: not Enum.empty?(Map.keys(retrieval_results.fusion_metadata))
    }
  end

  defp record_stage_timing(generation, stage) do
    current_time = System.monotonic_time(:microsecond)

    put_in(
      generation,
      [:telemetry_metadata, :stage_timings, stage],
      current_time - generation.telemetry_metadata.pipeline_start_time
    )
  end

  defp determine_current_stage(generation) do
    stage_checks = [
      {:halted, generation.halted?},
      {:evaluation_complete, evaluation_complete?(generation)},
      {:response_generated, response_generated?(generation)},
      {:prompt_enhanced, prompt_enhanced?(generation)},
      {:prompt_built, prompt_built?(generation)},
      {:context_built, context_built?(generation)},
      {:retrieval_complete, retrieval_complete?(generation)},
      {:embedding_generated, embedding_generated?(generation)},
      {:query_received, query_received?(generation)}
    ]

    find_current_stage(stage_checks, :initialized)
  end

  defp find_current_stage([], default_stage), do: default_stage

  defp find_current_stage([{stage, true} | _], _default_stage), do: stage

  defp find_current_stage([{_stage, false} | rest], default_stage) do
    find_current_stage(rest, default_stage)
  end

  defp evaluation_complete?(generation) do
    not is_nil(generation.evaluations.rag_triad.context_relevance_score)
  end

  defp response_generated?(generation) do
    not is_nil(generation.response)
  end

  defp prompt_enhanced?(generation) do
    generation.prompt_enhanced
  end

  defp prompt_built?(generation) do
    not is_nil(generation.prompt)
  end

  defp context_built?(generation) do
    not is_nil(generation.context)
  end

  defp retrieval_complete?(generation) do
    not Enum.empty?(generation.retrieval_results.fused_results)
  end

  defp embedding_generated?(generation) do
    not is_nil(generation.query_embedding)
  end

  defp query_received?(generation) do
    not is_nil(generation.query)
  end
end
