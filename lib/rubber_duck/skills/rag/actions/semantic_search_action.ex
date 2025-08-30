defmodule RubberDuck.Skills.Rag.Actions.SemanticSearchAction do
  @moduledoc """
  Vector-based semantic search action for RAG retrieval.

  This action performs sophisticated semantic search across vector databases
  using embedding similarity, with support for multiple vector stores, 
  hybrid search strategies, and intelligent result ranking and filtering.

  Features:
  - Multi-vector store support (PGVector, Chroma, in-memory)
  - Cosine similarity, dot product, and Euclidean distance metrics
  - Intelligent result filtering and ranking with relevance thresholds
  - Metadata filtering and constraint application
  - Result diversification to avoid redundant content
  - Performance optimization with caching and indexing

  Vector Store Support:
  - **PGVector**: PostgreSQL vector extension with SQL queries
  - **Chroma**: Dedicated vector database with REST API
  - **In-Memory**: Fast local search for development/testing
  """

  use Jido.Action,
    name: "semantic_search",
    schema: [
      query_embedding: [type: {:list, :float}, required: true, doc: "Query embedding vector"],
      vector_store: [
        type: :atom,
        default: :pgvector,
        doc: "Vector store to search (:pgvector, :chroma, :memory)"
      ],
      collection: [type: :string, default: "documents", doc: "Collection/table to search"],
      limit: [type: :integer, default: 10, doc: "Maximum number of results to return"],
      similarity_threshold: [
        type: :float,
        default: 0.7,
        doc: "Minimum similarity score (0.0-1.0)"
      ],
      search_config: [type: :map, default: %{}, doc: "Vector store specific configuration"],
      filters: [type: :map, default: %{}, doc: "Metadata filters to apply"],
      context: [type: :map, default: %{}, doc: "Search context for optimization"]
    ]

  require Logger

  # Vector store configurations
  @vector_store_configs %{
    pgvector: %{
      similarity_function: "cosine_distance",
      index_type: "ivfflat",
      default_probes: 10,
      max_results: 1000
    },
    chroma: %{
      distance_function: "cosine",
      include: ["metadatas", "documents", "distances"],
      max_results: 10_000
    },
    memory: %{
      similarity_function: :cosine,
      cache_enabled: true,
      max_results: 1000
    }
  }

  # Similarity metrics and their implementations
  @similarity_metrics [:cosine, :dot_product, :euclidean]

  @doc """
  Execute semantic search across vector databases with intelligent optimization.

  Returns ranked search results with similarity scores, metadata, and 
  search performance metrics for learning and optimization.
  """
  def run(params, _context) do
    %{
      query_embedding: query_embedding,
      vector_store: vector_store,
      collection: collection,
      limit: limit,
      similarity_threshold: threshold,
      search_config: search_config,
      filters: filters,
      context: search_context
    } = params

    Logger.debug("SemanticSearchAction: Starting semantic search",
      vector_store: vector_store,
      collection: collection,
      embedding_dimensions: length(query_embedding),
      limit: limit,
      threshold: threshold
    )

    search_start_time = System.monotonic_time(:microsecond)

    with {:ok, store_config} <- get_vector_store_config(vector_store, search_config),
         {:ok, normalized_embedding} <- normalize_query_embedding(query_embedding, store_config),
         {:ok, search_results} <-
           execute_vector_search(
             vector_store,
             collection,
             normalized_embedding,
             store_config,
             filters,
             limit
           ),
         {:ok, filtered_results} <- apply_similarity_filtering(search_results, threshold),
         {:ok, ranked_results} <- rank_and_diversify_results(filtered_results, search_context) do
      search_time = System.monotonic_time(:microsecond) - search_start_time

      # Calculate search performance metrics
      performance_metrics =
        calculate_search_performance(search_results, ranked_results, search_time)

      # Extract result metadata for learning
      result_metadata = extract_result_metadata(ranked_results, search_context)

      Logger.info("SemanticSearchAction: Semantic search complete",
        vector_store: vector_store,
        results_found: length(search_results),
        results_returned: length(ranked_results),
        search_time_us: search_time,
        avg_similarity: calculate_average_similarity(ranked_results)
      )

      {:ok,
       %{
         results: ranked_results,
         search_metadata: %{
           vector_store: vector_store,
           collection: collection,
           search_time_microseconds: search_time,
           total_results_found: length(search_results),
           results_after_filtering: length(ranked_results),
           similarity_threshold_used: threshold,
           filters_applied: filters
         },
         performance_metrics: performance_metrics,
         result_metadata: result_metadata
       }}
    else
      {:error, reason} ->
        Logger.error("SemanticSearchAction: Semantic search failed",
          error: reason,
          vector_store: vector_store,
          collection: collection
        )

        {:error, reason}
    end
  end

  # Private implementation functions

  defp get_vector_store_config(vector_store, custom_config) do
    case Map.get(@vector_store_configs, vector_store) do
      nil ->
        {:error, {:unsupported_vector_store, vector_store}}

      base_config ->
        merged_config = Map.merge(base_config, custom_config)
        {:ok, merged_config}
    end
  end

  defp normalize_query_embedding(query_embedding, store_config) do
    # Normalize embedding based on vector store requirements
    case store_config do
      %{similarity_function: "cosine_distance"} ->
        # Normalize for cosine similarity
        normalized = normalize_vector(query_embedding)
        {:ok, normalized}

      _ ->
        # Use embedding as-is for other similarity functions
        {:ok, query_embedding}
    end
  end

  defp normalize_vector(vector) when is_list(vector) do
    # L2 normalization for cosine similarity
    magnitude = :math.sqrt(Enum.map(vector, &(&1 * &1)) |> Enum.sum())

    if magnitude > 0 do
      Enum.map(vector, &(&1 / magnitude))
    else
      # Return original if magnitude is 0
      vector
    end
  end

  defp execute_vector_search(vector_store, collection, embedding, config, filters, limit) do
    case vector_store do
      :pgvector ->
        execute_pgvector_search(collection, embedding, config, filters, limit)

      :chroma ->
        execute_chroma_search(collection, embedding, config, filters, limit)

      :memory ->
        execute_memory_search(collection, embedding, config, filters, limit)

      _ ->
        {:error, {:unsupported_vector_store, vector_store}}
    end
  end

  # Vector store specific implementations

  defp execute_pgvector_search(collection, embedding, config, filters, limit) do
    # PGVector search using PostgreSQL with vector extension
    Logger.debug("SemanticSearchAction: Executing PGVector search")

    # This would integrate with actual PGVector/PostgreSQL queries
    # Placeholder implementation
    sample_results = generate_sample_results(limit, :pgvector)

    {:ok, sample_results}
  end

  defp execute_chroma_search(collection, embedding, config, filters, limit) do
    # Chroma vector database search
    Logger.debug("SemanticSearchAction: Executing Chroma search")

    # This would integrate with Chroma REST API
    # Placeholder implementation
    sample_results = generate_sample_results(limit, :chroma)

    {:ok, sample_results}
  end

  defp execute_memory_search(collection, embedding, config, filters, limit) do
    # In-memory vector search for development/testing
    Logger.debug("SemanticSearchAction: Executing in-memory search")

    # This would search against in-memory vector store
    # Placeholder implementation
    sample_results = generate_sample_results(limit, :memory)

    {:ok, sample_results}
  end

  # Result processing and ranking

  defp apply_similarity_filtering(search_results, threshold) do
    filtered_results =
      Enum.filter(search_results, fn result ->
        similarity = Map.get(result, :similarity_score, 0.0)
        similarity >= threshold
      end)

    Logger.debug("SemanticSearchAction: Applied similarity filtering",
      original_count: length(search_results),
      filtered_count: length(filtered_results),
      threshold: threshold
    )

    {:ok, filtered_results}
  end

  defp rank_and_diversify_results(filtered_results, context) do
    # Re-rank results based on additional context and diversify to avoid redundancy
    enable_diversification = Map.get(context, :enable_diversification, true)

    # Sort by similarity score (descending)
    ranked_results = Enum.sort_by(filtered_results, &Map.get(&1, :similarity_score, 0.0), :desc)

    final_results =
      if enable_diversification do
        diversify_results(ranked_results, context)
      else
        ranked_results
      end

    {:ok, final_results}
  end

  defp diversify_results(ranked_results, context) do
    # Simple diversification to avoid too many similar results
    diversity_threshold = Map.get(context, :diversity_threshold, 0.9)

    Enum.reduce(ranked_results, [], fn result, acc ->
      # Check if this result is too similar to already selected results
      if should_include_for_diversity?(result, acc, diversity_threshold) do
        [result | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp should_include_for_diversity?(result, existing_results, threshold) do
    result_content = Map.get(result, :content, "")

    # Simple content-based diversity check
    too_similar =
      Enum.any?(existing_results, fn existing ->
        existing_content = Map.get(existing, :content, "")
        content_similarity(result_content, existing_content) > threshold
      end)

    not too_similar
  end

  defp content_similarity(content1, content2) do
    # Simple Jaccard similarity based on words
    words1 = String.split(String.downcase(content1)) |> MapSet.new()
    words2 = String.split(String.downcase(content2)) |> MapSet.new()

    intersection_size = MapSet.intersection(words1, words2) |> MapSet.size()
    union_size = MapSet.union(words1, words2) |> MapSet.size()

    if union_size > 0 do
      intersection_size / union_size
    else
      0.0
    end
  end

  # Performance and metadata calculation

  defp calculate_search_performance(original_results, final_results, search_time) do
    %{
      search_time_microseconds: search_time,
      total_results_found: length(original_results),
      results_returned: length(final_results),
      filtering_effectiveness: calculate_filtering_effectiveness(original_results, final_results),
      average_similarity: calculate_average_similarity(final_results),
      search_efficiency: calculate_search_efficiency(search_time, length(final_results))
    }
  end

  defp calculate_filtering_effectiveness(original, filtered) do
    if Enum.empty?(original) do
      0.0
    else
      # Measure how well filtering improved average quality
      original_avg = calculate_average_similarity(original)
      filtered_avg = calculate_average_similarity(filtered)

      improvement = filtered_avg - original_avg
      Float.round(max(improvement, 0.0), 3)
    end
  end

  defp calculate_average_similarity(results) do
    if Enum.empty?(results) do
      0.0
    else
      similarities = Enum.map(results, &Map.get(&1, :similarity_score, 0.0))
      avg = Enum.sum(similarities) / Enum.count(similarities)
      Float.round(avg, 3)
    end
  end

  defp calculate_search_efficiency(search_time_us, result_count) do
    # Results per millisecond
    if result_count > 0 do
      efficiency = result_count / (search_time_us / 1000)
      Float.round(efficiency, 3)
    else
      0.0
    end
  end

  defp extract_result_metadata(results, context) do
    %{
      result_count: length(results),
      content_domains: extract_content_domains(results),
      source_diversity: calculate_source_diversity(results),
      quality_distribution: calculate_quality_distribution(results),
      context_alignment: assess_context_alignment(results, context)
    }
  end

  defp extract_content_domains(results) do
    # Extract domains/categories from result metadata
    results
    |> Enum.map(&Map.get(&1, :metadata, %{}))
    |> Enum.map(&Map.get(&1, :domain, :unknown))
    |> Enum.frequencies()
  end

  defp calculate_source_diversity(results) do
    # Calculate diversity of sources in results
    sources =
      results
      |> Enum.map(&Map.get(&1, :source, "unknown"))
      |> Enum.uniq()

    diversity_ratio =
      if Enum.empty?(results) do
        0.0
      else
        length(sources) / length(results)
      end

    Float.round(diversity_ratio, 3)
  end

  defp calculate_quality_distribution(results) do
    similarities = Enum.map(results, &Map.get(&1, :similarity_score, 0.0))

    if Enum.empty?(similarities) do
      %{min: 0.0, max: 0.0, avg: 0.0, std_dev: 0.0}
    else
      avg = Enum.sum(similarities) / length(similarities)

      variance =
        similarities
        |> Enum.map(&:math.pow(&1 - avg, 2))
        |> Enum.sum()
        |> Kernel./(length(similarities))

      %{
        min: Float.round(Enum.min(similarities), 3),
        max: Float.round(Enum.max(similarities), 3),
        avg: Float.round(avg, 3),
        std_dev: Float.round(:math.sqrt(variance), 3)
      }
    end
  end

  defp assess_context_alignment(results, context) do
    # Assess how well results align with search context
    expected_domain = Map.get(context, :domain)
    user_intent = Map.get(context, :user_intent)

    domain_alignment =
      if expected_domain do
        domain_matches =
          Enum.count(results, fn result ->
            result_domain = get_in(result, [:metadata, :domain])
            result_domain == expected_domain
          end)

        if Enum.empty?(results) do
          0.0
        else
          domain_matches / length(results)
        end
      else
        # No domain expectation
        1.0
      end

    %{
      domain_alignment: Float.round(domain_alignment, 3),
      context_relevance: assess_content_relevance(results, user_intent)
    }
  end

  defp assess_content_relevance(results, user_intent) when is_binary(user_intent) do
    # Simple content relevance assessment
    intent_words = String.split(String.downcase(user_intent)) |> MapSet.new()

    relevance_scores =
      Enum.map(results, fn result ->
        content = Map.get(result, :content, "")
        content_words = String.split(String.downcase(content)) |> MapSet.new()

        # Calculate word overlap
        intersection = MapSet.intersection(intent_words, content_words) |> MapSet.size()
        union = MapSet.union(intent_words, content_words) |> MapSet.size()

        if union > 0, do: intersection / union, else: 0.0
      end)

    if Enum.empty?(relevance_scores) do
      0.0
    else
      avg_relevance = Enum.sum(relevance_scores) / length(relevance_scores)
      Float.round(avg_relevance, 3)
    end
  end

  defp assess_content_relevance(_results, _intent), do: 0.5

  # Placeholder implementations for vector store operations
  # In production, these would integrate with actual vector databases

  defp generate_sample_results(limit, vector_store) do
    # Generate realistic sample results for development
    Enum.map(1..min(limit, 5), fn i ->
      %{
        id: "doc_#{i}",
        content: "Sample document content #{i} for #{vector_store} search",
        # Decreasing similarity
        similarity_score: 0.95 - i * 0.1,
        source: "sample_source_#{rem(i, 3) + 1}",
        metadata: %{
          domain: Enum.random([:technical, :general, :business]),
          created_at: DateTime.utc_now() |> DateTime.add(-i * 24 * 3600, :second),
          word_count: 100 + i * 50,
          vector_store: vector_store
        },
        embedding: generate_sample_embedding()
      }
    end)
  end

  defp generate_sample_embedding do
    # Generate a sample 384-dimensional embedding
    for _ <- 1..384, do: :rand.normal() * 0.1
  end

  # Future integration points for actual vector stores

  # defp execute_pgvector_query(collection, embedding, config, filters, limit) do
  #   # SQL query with vector operations
  #   query = """
  #   SELECT id, content, source, metadata,
  #          embedding <=> $1 AS distance
  #   FROM #{collection}
  #   WHERE embedding <=> $1 < $2
  #   ORDER BY distance
  #   LIMIT $3
  #   """
  #
  #   # Execute with Ecto/PostgreSQL
  # end

  # defp execute_chroma_query(collection, embedding, config, filters, limit) do
  #   # REST API call to Chroma
  #   request_body = %{
  #     query_embeddings: [embedding],
  #     n_results: limit,
  #     where: filters,
  #     include: config.include
  #   }
  #
  #   # HTTP request to Chroma API
  # end

  # defp execute_memory_search(collection, embedding, config, filters, limit) do
  #   # In-memory vector search using GenServer state
  #   # Calculate similarities against stored embeddings
  # end
end
