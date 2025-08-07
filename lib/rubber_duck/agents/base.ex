defmodule RubberDuck.Agents.Base do
  @moduledoc """
  Base behavior for RubberDuck agents.

  Provides common functionality for all agents including:
  - Goal management
  - Learning capabilities
  - Experience tracking
  - Common signal handling
  """

  defmacro __using__(opts) do
    quote location: :keep do
      use Jido.Agent, unquote(opts)
      require Logger

      # Import the learning and persistence actions
      alias RubberDuck.Actions.Agent.{Learn, LoadAgentState, SaveAgentState}

      # Import message routing support
      alias RubberDuck.Routing.MessageRouter
      alias RubberDuck.Adapters.SignalAdapter
      alias RubberDuck.Messages

      # Define child_spec for supervision
      def child_spec(opts) do
        id = Keyword.get(opts, :id, __MODULE__)

        %{
          id: id,
          start: {__MODULE__, :start_link, [opts]},
          restart: :permanent,
          shutdown: 5000,
          type: :worker
        }
      end

      # Start link function
      def start_link(opts \\ []) do
        # Extract the id for process registration
        id = Keyword.get(opts, :id)

        # Create the agent instance with merged options
        agent_opts = if id, do: [id: id], else: []
        agent = __MODULE__.new(agent_opts)

        # Load persisted state if enabled
        agent =
          if Map.get(agent.state, :persistence_enabled, false) do
            case load_persisted_state(agent) do
              {:ok, loaded_agent} ->
                Logger.info("Loaded persisted state for agent #{agent.name}")
                # Schedule first checkpoint
                schedule_checkpoint(loaded_agent)
                loaded_agent

              {:error, reason} ->
                Logger.warning(
                  "Failed to load persisted state for agent #{agent.name}: #{inspect(reason)}"
                )

                # Schedule checkpoint for new agent
                schedule_checkpoint(agent)
                agent
            end
          else
            agent
          end

        # Build server options
        server_opts = [
          agent: agent,
          pubsub: RubberDuck.PubSub,
          name: if(id, do: String.to_atom("#{__MODULE__}.#{id}"), else: __MODULE__)
        ]

        # Start the agent server
        Jido.Agent.Server.start_link(server_opts)
      end

      # Common callbacks that can be overridden

      @doc """
      Called when a new goal is assigned to the agent.
      """
      def on_goal_assigned(agent, goal) do
        updated_goals = [goal | agent.state.goals]
        {:ok, %{agent | state: Map.put(agent.state, :goals, updated_goals)}}
      end

      @doc """
      Called when a goal is completed.
      """
      def on_goal_completed(agent, goal, result) do
        # Move goal to completed
        remaining_goals = Enum.reject(agent.state.goals, &(&1.id == goal.id))
        completed = [Map.put(goal, :result, result) | agent.state.completed_goals]

        updated_state =
          agent.state
          |> Map.put(:goals, remaining_goals)
          |> Map.put(:completed_goals, completed)

        # Learn from the experience if enabled
        agent_with_updated_state = %{agent | state: updated_state}

        if agent.state.learning_enabled do
          on_experience_gained(agent_with_updated_state, %{
            goal: goal,
            result: result,
            timestamp: DateTime.utc_now()
          })
        else
          {:ok, agent_with_updated_state}
        end
      end

      @doc """
      Called when the agent gains new experience.
      """
      def on_experience_gained(agent, experience) do
        unless is_map(experience) do
          throw({:error, :invalid_experience})
        end

        updated_experience = [experience | agent.state.experience]

        # Keep only recent experience based on max_memory_experiences setting
        max_experiences = agent.state[:max_memory_experiences] || 1000
        trimmed_experience = Enum.take(updated_experience, max_experiences)

        updated_agent = %{agent | state: Map.put(agent.state, :experience, trimmed_experience)}

        # Check if it's time to learn
        if should_trigger_learning?(updated_agent) do
          perform_learning(updated_agent)
        else
          {:ok, updated_agent}
        end
      rescue
        exception ->
          Logger.error("Experience recording failed: #{inspect(exception)}")
          # Continue with unchanged agent
          {:ok, agent}
      catch
        {:error, reason} ->
          Logger.warning("Failed to record experience: #{inspect(reason)}")
          # Continue with unchanged agent
          {:ok, agent}
      end

      @doc """
      Extract patterns from agent's experience.
      """
      def analyze_experience(agent) do
        agent.state.experience
        |> filter_valid_experiences()
        |> group_experiences_by_type()
        |> calculate_experience_metrics()
      rescue
        exception ->
          Logger.warning("Experience analysis failed: #{inspect(exception)}")
          # Return empty analysis on error
          %{}
      end

      defp filter_valid_experiences(experiences) do
        Enum.filter(experiences, &valid_experience_entry?/1)
      end

      defp valid_experience_entry?(experience) do
        is_map(experience) && Map.has_key?(experience, :goal) && is_map(experience.goal)
      end

      defp group_experiences_by_type(experiences) do
        Enum.group_by(experiences, & &1.goal[:type])
      end

      defp calculate_experience_metrics(grouped_experiences) do
        grouped_experiences
        |> Enum.map(&build_experience_metrics/1)
        |> Map.new()
      end

      defp build_experience_metrics({type, experiences}) do
        {type,
         %{
           success_rate: calculate_success_rate(experiences),
           avg_duration: calculate_average_duration(experiences),
           sample_size: length(experiences)
         }}
      end

      @doc """
      Get current performance metrics.
      """
      def get_performance_metrics(agent) do
        Map.merge(
          %{
            total_goals: length(agent.state.goals) + length(agent.state.completed_goals),
            active_goals: length(agent.state.goals),
            completed_goals: length(agent.state.completed_goals),
            experience_entries: length(agent.state.experience)
          },
          agent.state.performance_metrics
        )
      end

      # Private helper functions

      defp calculate_success_rate(experiences) do
        total = length(experiences)

        if total == 0 do
          0.0
        else
          successful = Enum.count(experiences, &(&1.result[:success] == true))
          successful / total
        end
      end

      defp calculate_average_duration(experiences) do
        durations =
          experiences
          |> Enum.map(& &1.result[:duration_ms])
          |> Enum.filter(&is_number/1)

        if Enum.empty?(durations) do
          0
        else
          Enum.sum(durations) / length(durations)
        end
      end

      @doc """
      Perform learning based on accumulated experiences.
      """
      def perform_learning(agent) do
        case can_perform_learning?(agent) do
          true -> execute_learning_process(agent)
          false -> {:ok, agent}
        end
      end

      defp can_perform_learning?(agent) do
        agent.state.learning_enabled && length(agent.state.experience) >= 10
      end

      defp execute_learning_process(agent) do
        insights = gather_learning_insights(agent)

        case map_size(insights) do
          0 -> {:ok, agent}
          _ -> store_learned_insights(agent, insights)
        end
      end

      defp gather_learning_insights(agent) do
        learning_types = [:pattern, :correlation, :optimization]

        Enum.reduce(learning_types, %{}, fn type, acc ->
          collect_insight_for_type(agent, type, acc)
        end)
      end

      defp collect_insight_for_type(agent, type, acc) do
        case Learn.run(
               %{
                 experiences: agent.state.experience,
                 learning_type: type,
                 context: %{agent_name: agent.name}
               },
               %{}
             ) do
          {:ok, result} when result.learned ->
            Map.put(acc, type, result.insights)

          _ ->
            acc
        end
      end

      defp store_learned_insights(agent, insights) do
        Logger.info("Agent #{agent.name} learned new insights: #{inspect(Map.keys(insights))}")

        updated_state =
          agent.state
          |> Map.put(:learned_insights, Map.merge(agent.state.learned_insights, insights))
          |> Map.put(:last_learning_at, NaiveDateTime.utc_now())

        {:ok, %{agent | state: updated_state}}
      end

      @doc """
      Apply learned insights to make better decisions.
      """
      def apply_learned_insights(agent, decision_context) do
        insights = agent.state.learned_insights

        recommendations = []

        # Apply pattern insights
        if patterns = insights[:pattern] do
          pattern_recs = patterns[:recommendations] || []
          recommendations = recommendations ++ pattern_recs
        end

        # Apply correlation insights
        if correlations = insights[:correlation] do
          correlation_recs = correlations[:correlation_insights] || []
          recommendations = recommendations ++ correlation_recs
        end

        # Apply optimization insights
        if optimizations = insights[:optimization] do
          opt_recs = optimizations[:recommended_actions] || []
          recommendations = recommendations ++ opt_recs
        end

        %{
          recommendations: recommendations,
          confidence: calculate_insight_confidence(insights),
          applicable: insight_applicable?(insights, decision_context)
        }
      end

      # Private helper functions

      defp should_trigger_learning?(agent) do
        experience_count = length(agent.state.experience)

        # Learn when we have enough new experiences
        since_last_learning =
          if agent.state.last_learning_at do
            experiences_since_learning =
              Enum.count(agent.state.experience, fn exp ->
                exp[:timestamp] &&
                  NaiveDateTime.compare(exp[:timestamp], agent.state.last_learning_at) == :gt
              end)

            experiences_since_learning
          else
            experience_count
          end

        agent.state.learning_enabled &&
          experience_count >= 10 &&
          since_last_learning >= agent.state.learning_interval
      end

      defp calculate_insight_confidence(insights) do
        if map_size(insights) == 0 do
          0.0
        else
          # Average confidence across all insight types
          confidences =
            insights
            |> Map.values()
            |> Enum.map(fn insight ->
              # Default confidence
              insight[:pattern_confidence] ||
                insight[:prediction_accuracy] ||
                0.7
            end)

          Enum.sum(confidences) / length(confidences)
        end
      end

      defp insight_applicable?(insights, context) do
        # Check if any insights are relevant to the current context
        applicable_scenarios =
          insights
          |> Map.values()
          |> Enum.flat_map(fn insight ->
            insight[:applicable_scenarios] || []
          end)

        # Simple check - in production would do more sophisticated matching
        length(applicable_scenarios) > 0
      end

      # Persistence functions

      @doc """
      Load persisted state for the agent.
      """
      def load_persisted_state(agent) do
        case LoadAgentState.run(
               %{
                 agent_name: agent.name,
                 load_experiences: true,
                 experience_limit: agent.state.max_memory_experiences
               },
               %{}
             ) do
          {:ok, state_data} ->
            if state_data[:new_agent] do
              {:ok, agent}
            else
              # Merge loaded state with current agent
              updated_state =
                agent.state
                |> Map.put(:agent_state_id, state_data.agent_state_id)
                |> Map.put(:last_checkpoint, state_data.last_checkpoint)
                |> Map.merge(state_data.metadata || %{})
                |> Map.put(:experience, state_data[:experiences] || [])
                |> Map.put(:learned_insights, state_data[:insights] || %{})
                |> maybe_put_provider_performance(state_data)

              {:ok, %{agent | state: updated_state}}
            end

          error ->
            error
        end
      end

      defp maybe_put_provider_performance(state, state_data) do
        if state_data[:provider_performance] do
          Map.put(state, :provider_performance, state_data.provider_performance)
        else
          state
        end
      end

      @doc """
      Schedule periodic checkpoints for the agent.
      """
      def schedule_checkpoint(agent) do
        if agent.state.persistence_enabled && agent.state.checkpoint_interval > 0 do
          Process.send_after(self(), :checkpoint, agent.state.checkpoint_interval)
        end

        agent
      end

      @doc """
      Perform a checkpoint to persist agent state.
      """
      def on_checkpoint(agent) do
        if agent.state.persistence_enabled do
          case SaveAgentState.run(
                 %{
                   agent: agent,
                   include_experiences: true,
                   experience_batch_size: 100
                 },
                 %{}
               ) do
            {:ok, result} ->
              Logger.debug("Agent #{agent.name} checkpoint completed: #{inspect(result)}")
              # Schedule next checkpoint
              schedule_checkpoint(agent)

              # Update last checkpoint time
              {:ok, %{agent | state: Map.put(agent.state, :last_checkpoint, DateTime.utc_now())}}

            {:error, reason} ->
              Logger.error("Agent #{agent.name} checkpoint failed: #{inspect(reason)}")
              # Schedule retry
              # Retry in 1 minute
              Process.send_after(self(), :checkpoint, 60_000)
              {:ok, agent}
          end
        else
          {:ok, agent}
        end
      end

      @doc """
      Handle agent shutdown by saving final state.
      """
      def on_shutdown(agent) do
        if agent.state.persistence_enabled do
          Logger.info("Saving final state for agent #{agent.name}")

          case SaveAgentState.run(
                 %{
                   agent: agent,
                   include_experiences: true,
                   experience_batch_size: 100
                 },
                 %{}
               ) do
            {:ok, _} ->
              Logger.info("Final state saved for agent #{agent.name}")

            {:error, reason} ->
              Logger.error(
                "Failed to save final state for agent #{agent.name}: #{inspect(reason)}"
              )
          end
        end

        {:ok, agent}
      end

      # The agent server handles the GenServer callbacks
      # We need to provide agent behavior callbacks instead

      @doc """
      Handle agent termination.
      """
      def terminate(reason, agent) do
        Logger.info("Agent #{agent.name} terminating: #{inspect(reason)}")
        on_shutdown(agent)
        :ok
      end

      # Make callbacks overridable
      defoverridable on_goal_assigned: 2,
                     on_goal_completed: 3,
                     on_experience_gained: 2,
                     analyze_experience: 1,
                     get_performance_metrics: 1,
                     perform_learning: 1,
                     apply_learned_insights: 2,
                     load_persisted_state: 1,
                     schedule_checkpoint: 1,
                     on_checkpoint: 1,
                     on_shutdown: 1,
                     terminate: 2
    end
  end
end
