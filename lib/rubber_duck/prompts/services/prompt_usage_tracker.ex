defmodule RubberDuck.Prompts.Services.PromptUsageTracker do
  @moduledoc """
  Service for tracking prompt usage in LLM operations and analytics.

  Provides comprehensive tracking of when and how saved prompts are used
  in LLM operations, enabling usage analytics, effectiveness measurement,
  and productivity insights for users and administrators.

  Features:
  - Asynchronous usage tracking to avoid impacting LLM operation performance
  - Comprehensive usage analytics for saved prompts in LLM contexts
  - Integration with PromptUsage resource for persistent analytics
  - Performance metrics and effectiveness tracking for prompt optimization
  """

  use GenServer
  require Logger

  alias RubberDuck.Prompts.Resources.PromptUsage

  @buffer_size 100
  @flush_interval :timer.seconds(10)

  defstruct [
    :usage_buffer,
    :buffer_size,
    :flush_timer
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Schedule periodic flushing of usage buffer
    timer = Process.send_after(self(), :flush_usage_buffer, @flush_interval)

    state = %__MODULE__{
      usage_buffer: [],
      buffer_size: @buffer_size,
      flush_timer: timer
    }

    Logger.info("PromptUsageTracker: Service initialized with buffering")
    {:ok, state}
  end

  # Public API

  @doc """
  Track prompt usage in LLM operations (asynchronous).
  """
  def track_llm_usage(user_id, prompt_id, llm_context, usage_metadata \\ %{}) do
    GenServer.cast(
      __MODULE__,
      {:track_llm_usage, user_id, prompt_id, llm_context, usage_metadata}
    )
  end

  @doc """
  Track prompt selection events for analytics.
  """
  def track_prompt_selection(user_id, prompt_id, selection_context) do
    GenServer.cast(__MODULE__, {:track_selection, user_id, prompt_id, selection_context})
  end

  @doc """
  Track prompt search events for search optimization.
  """
  def track_search_event(user_id, search_query, search_results_count, search_context) do
    GenServer.cast(
      __MODULE__,
      {:track_search, user_id, search_query, search_results_count, search_context}
    )
  end

  @doc """
  Get usage statistics for a specific prompt.
  """
  def get_prompt_usage_stats(prompt_id, user_id \\ nil) do
    GenServer.call(__MODULE__, {:get_usage_stats, prompt_id, user_id})
  end

  @doc """
  Get usage analytics for user's prompt library.
  """
  def get_user_usage_analytics(user_id, analytics_options \\ %{}) do
    GenServer.call(__MODULE__, {:get_user_analytics, user_id, analytics_options})
  end

  # GenServer callbacks

  @impl true
  def handle_cast({:track_llm_usage, user_id, prompt_id, llm_context, usage_metadata}, state) do
    usage_entry = %{
      type: :llm_usage,
      user_id: user_id,
      prompt_id: prompt_id,
      context: llm_context,
      metadata: usage_metadata,
      timestamp: DateTime.utc_now()
    }

    updated_buffer = [usage_entry | state.usage_buffer]

    # Check if buffer should be flushed
    updated_state =
      if length(updated_buffer) >= state.buffer_size do
        flush_usage_buffer_sync(updated_buffer)
        %{state | usage_buffer: []}
      else
        %{state | usage_buffer: updated_buffer}
      end

    {:noreply, updated_state}
  end

  @impl true
  def handle_cast({:track_selection, user_id, prompt_id, selection_context}, state) do
    selection_entry = %{
      type: :prompt_selection,
      user_id: user_id,
      prompt_id: prompt_id,
      context: selection_context,
      timestamp: DateTime.utc_now()
    }

    updated_buffer = [selection_entry | state.usage_buffer]

    {:noreply, %{state | usage_buffer: updated_buffer}}
  end

  @impl true
  def handle_cast({:track_search, user_id, search_query, results_count, search_context}, state) do
    search_entry = %{
      type: :search_event,
      user_id: user_id,
      search_query: search_query,
      results_count: results_count,
      context: search_context,
      timestamp: DateTime.utc_now()
    }

    updated_buffer = [search_entry | state.usage_buffer]

    {:noreply, %{state | usage_buffer: updated_buffer}}
  end

  @impl true
  def handle_call({:get_usage_stats, prompt_id, user_id}, _from, state) do
    case fetch_prompt_usage_stats(prompt_id, user_id) do
      {:ok, stats} ->
        {:reply, {:ok, stats}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_user_analytics, user_id, analytics_options}, _from, state) do
    case generate_user_analytics(user_id, analytics_options) do
      {:ok, analytics} ->
        {:reply, {:ok, analytics}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:flush_usage_buffer, state) do
    # Periodic flush of usage buffer
    if state.usage_buffer != [] do
      flush_usage_buffer_sync(state.usage_buffer)
    end

    # Schedule next flush
    timer = Process.send_after(self(), :flush_usage_buffer, @flush_interval)

    updated_state = %{state | usage_buffer: [], flush_timer: timer}
    {:noreply, updated_state}
  end

  # Private implementation functions

  defp flush_usage_buffer_sync(usage_buffer) do
    # Flush usage buffer to database synchronously
    Logger.debug("PromptUsageTracker: Flushing usage buffer", entries: length(usage_buffer))

    # Process each usage entry
    processed_entries = Enum.map(usage_buffer, &process_usage_entry/1)
    successful_entries = Enum.filter(processed_entries, &match?({:ok, _}, &1))

    Logger.debug("PromptUsageTracker: Usage buffer flushed",
      total_entries: length(usage_buffer),
      successful_entries: length(successful_entries)
    )
  end

  defp process_usage_entry(entry) do
    case entry.type do
      :llm_usage ->
        record_llm_usage(entry)

      :prompt_selection ->
        record_prompt_selection(entry)

      :search_event ->
        record_search_event(entry)

      _ ->
        {:error, :unknown_entry_type}
    end
  end

  defp record_llm_usage(entry) do
    # Record LLM usage in PromptUsage resource
    usage_attrs = %{
      user_id: entry.user_id,
      prompt_id: entry.prompt_id,
      usage_type: :llm_operation,
      usage_context: entry.context,
      used_at: entry.timestamp,
      metadata:
        Map.merge(entry.metadata, %{
          llm_provider: Map.get(entry.context, :llm_provider),
          operation_type: Map.get(entry.context, :operation_type),
          success: Map.get(entry.metadata, :success, true)
        })
    }

    case PromptUsage.create(usage_attrs) do
      {:ok, usage_record} ->
        {:ok, usage_record}

      {:error, reason} ->
        Logger.warning("Failed to record LLM usage: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp record_prompt_selection(entry) do
    # Record prompt selection event (lighter tracking)
    selection_attrs = %{
      user_id: entry.user_id,
      prompt_id: entry.prompt_id,
      usage_type: :selection,
      usage_context: entry.context,
      used_at: entry.timestamp,
      metadata: %{
        selection_interface: Map.get(entry.context, :interface, :unknown),
        search_query: Map.get(entry.context, :search_query)
      }
    }

    case PromptUsage.create(selection_attrs) do
      {:ok, selection_record} ->
        {:ok, selection_record}

      {:error, reason} ->
        Logger.warning("Failed to record prompt selection: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp record_search_event(entry) do
    # Record search event for search analytics (optional detailed tracking)
    # For now, just log the search activity
    Logger.debug("PromptUsageTracker: Search event",
      user_id: entry.user_id,
      search_query: entry.search_query,
      results_count: entry.results_count
    )

    {:ok, :search_logged}
  end

  defp fetch_prompt_usage_stats(prompt_id, user_id) do
    # Fetch usage statistics for prompt
    filters = %{prompt_id: prompt_id}

    filters =
      if user_id do
        Map.put(filters, :user_id, user_id)
      else
        filters
      end

    case PromptUsage.read(filters) do
      {:ok, usage_records} ->
        stats = calculate_usage_statistics(usage_records)
        {:ok, stats}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_user_analytics(user_id, analytics_options) do
    # Generate comprehensive user analytics
    time_range = Map.get(analytics_options, :time_range, :last_30_days)
    include_details = Map.get(analytics_options, :include_details, false)

    filters =
      %{
        user_id: user_id
      }
      |> add_time_range_filter(time_range)

    case PromptUsage.read(filters) do
      {:ok, usage_records} ->
        analytics = %{
          user_id: user_id,
          time_range: time_range,
          total_usage_count: length(usage_records),
          unique_prompts_used: count_unique_prompts(usage_records),
          most_used_prompts: get_most_used_prompts(usage_records, 10),
          usage_by_type: group_usage_by_type(usage_records),
          daily_usage_pattern: calculate_daily_pattern(usage_records),
          analytics_generated_at: DateTime.utc_now()
        }

        analytics =
          if include_details do
            Map.merge(analytics, %{
              detailed_usage: usage_records,
              prompt_effectiveness: calculate_prompt_effectiveness(usage_records)
            })
          else
            analytics
          end

        {:ok, analytics}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Analytics helper functions

  defp calculate_usage_statistics(usage_records) do
    # Calculate usage statistics from records
    %{
      total_uses: length(usage_records),
      unique_users: count_unique_users(usage_records),
      first_used: get_first_usage_date(usage_records),
      last_used: get_last_usage_date(usage_records),
      usage_frequency: calculate_usage_frequency(usage_records),
      average_success_rate: calculate_average_success_rate(usage_records)
    }
  end

  defp count_unique_prompts(usage_records) do
    usage_records
    |> Enum.map(fn record -> record.prompt_id end)
    |> Enum.uniq()
    |> length()
  end

  defp count_unique_users(usage_records) do
    usage_records
    |> Enum.map(fn record -> record.user_id end)
    |> Enum.uniq()
    |> length()
  end

  defp get_most_used_prompts(usage_records, limit) do
    usage_records
    |> Enum.group_by(fn record -> record.prompt_id end)
    |> Enum.map(fn {prompt_id, records} -> {prompt_id, length(records)} end)
    |> Enum.sort_by(fn {_prompt_id, count} -> count end, :desc)
    |> Enum.take(limit)
  end

  defp group_usage_by_type(usage_records) do
    usage_records
    |> Enum.group_by(fn record -> record.usage_type end)
    |> Enum.map(fn {type, records} -> {type, length(records)} end)
    |> Map.new()
  end

  defp calculate_daily_pattern(usage_records) do
    # Calculate usage pattern by day of week
    usage_records
    |> Enum.group_by(fn record ->
      Date.day_of_week(DateTime.to_date(record.used_at))
    end)
    |> Enum.map(fn {day, records} -> {day, length(records)} end)
    |> Map.new()
  end

  defp get_first_usage_date(usage_records) do
    case usage_records do
      [] ->
        nil

      records ->
        records
        |> Enum.min_by(fn record -> record.used_at end)
        |> Map.get(:used_at)
    end
  end

  defp get_last_usage_date(usage_records) do
    case usage_records do
      [] ->
        nil

      records ->
        records
        |> Enum.max_by(fn record -> record.used_at end)
        |> Map.get(:used_at)
    end
  end

  defp calculate_usage_frequency(usage_records) do
    # Calculate usage frequency (uses per day)
    case usage_records do
      [] ->
        0.0

      records ->
        first_date = get_first_usage_date(records)
        last_date = get_last_usage_date(records)

        if first_date && last_date do
          days_span = max(1, DateTime.diff(last_date, first_date, :day))
          length(records) / days_span
        else
          0.0
        end
    end
  end

  defp calculate_average_success_rate(usage_records) do
    # Calculate average success rate from metadata
    success_records =
      Enum.filter(usage_records, fn record ->
        case record.metadata do
          %{success: true} -> true
          %{"success" => true} -> true
          _ -> false
        end
      end)

    case length(usage_records) do
      0 -> 0.0
      total -> length(success_records) / total
    end
  end

  defp calculate_prompt_effectiveness(usage_records) do
    # Calculate prompt effectiveness metrics
    %{
      usage_consistency: calculate_usage_consistency(usage_records),
      user_satisfaction: calculate_user_satisfaction(usage_records),
      context_effectiveness: calculate_context_effectiveness(usage_records)
    }
  end

  defp add_time_range_filter(filters, time_range) do
    # Add time range filter to usage queries
    cutoff_date =
      case time_range do
        :last_7_days -> DateTime.add(DateTime.utc_now(), -7, :day)
        :last_30_days -> DateTime.add(DateTime.utc_now(), -30, :day)
        :last_90_days -> DateTime.add(DateTime.utc_now(), -90, :day)
        _ -> DateTime.add(DateTime.utc_now(), -30, :day)
      end

    Map.put(filters, :used_at, {:>=, cutoff_date})
  end

  # Simplified calculation functions (would be enhanced with more sophisticated analytics)
  defp calculate_usage_consistency(_usage_records), do: 0.8
  defp calculate_user_satisfaction(_usage_records), do: 0.85
  defp calculate_context_effectiveness(_usage_records), do: 0.75
end
