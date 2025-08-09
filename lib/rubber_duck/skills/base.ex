defmodule RubberDuck.Skills.Base do
  @moduledoc """
  Base behavior for skills using typed messages.

  This module provides the foundation for all RubberDuck skills,
  supporting strongly-typed messages with compile-time validation.

  ## Usage

      defmodule MySkill do
        use RubberDuck.Skills.Base,
          name: "my_skill"
        
        # Handle typed messages
        def handle_analyze(%Code.Analyze{} = msg, state) do
          # Type-safe message handling
          {:ok, result, state}
        end
      end

  ## Message Handling

  Skills handle typed messages through specific handler functions
  that match the message type name. The framework automatically
  routes messages to the appropriate handler.
  """

  defmacro __using__(opts) do
    quote location: :keep do
      use Jido.Skill, unquote(opts)

      alias RubberDuck.Protocol.Message
      require Logger

      # Store the skill metadata
      @skill_name Keyword.get(unquote(opts), :name, "unnamed")

      # Override Jido's handle_signal to handle typed messages
      @impl true
      def handle_signal(signal, state) do
        # Log warning that signals are deprecated
        Logger.warning("[#{@skill_name}] Received legacy signal: #{inspect(signal[:type])}. Skills should use typed messages.")
        {:ok, state}
      end

      @doc """
      Handle typed messages by routing to specific handlers.
      """
      def handle_typed_message(message, state) when is_struct(message) do
        start_time = System.monotonic_time(:microsecond)

        result = route_typed_message(message, state)

        # Emit telemetry
        duration = System.monotonic_time(:microsecond) - start_time
        emit_message_telemetry(message, duration, result)

        result
      end

      # Route typed messages to specific handlers
      defp route_typed_message(message, state) do
        # Get the handler function name for this message type
        handler_function =
          message.__struct__
          |> Module.split()
          |> List.last()
          |> Macro.underscore()
          |> then(&:"handle_#{&1}")

        # Check if a specific handler exists
        if function_exported?(__MODULE__, handler_function, 2) do
          Logger.debug("[#{@skill_name}] Handling typed message: #{handler_function}")

          # Call the specific handler
          apply(__MODULE__, handler_function, [message, state])
        else
          # No specific handler, try generic handler
          if function_exported?(__MODULE__, :handle_message, 2) do
            Logger.debug("[#{@skill_name}] Using generic message handler")
            handle_message(message, state)
          else
            # No handler available
            Logger.debug(
              "[#{@skill_name}] No handler for message type: #{inspect(message.__struct__)}"
            )

            handle_message_default(message, state)
          end
        end
      rescue
        e ->
          Logger.error("[#{@skill_name}] Error handling message: #{inspect(e)}")
          {:error, e, state}
      end

      # Emit telemetry for monitoring
      defp emit_message_telemetry(message, duration, result) do
        success =
          case result do
            {:ok, _, _} -> true
            {:ok, _} -> true
            _ -> false
          end

        :telemetry.execute(
          [:rubber_duck, :skill, :message],
          %{duration: duration},
          %{
            skill: @skill_name,
            message_type: message.__struct__,
            success: success
          }
        )
      end

      # Default handlers (overrideable)
      @doc """
      Generic message handler for unmatched message types.
      Override this to provide custom handling.
      """
      def handle_message(_message, state) do
        {:ok, state}
      end

      @doc """
      Default handler for messages without specific handlers.
      Override this to customize default behavior.
      """
      def handle_message_default(_message, state) do
        {:ok, state}
      end

      @doc """
      Legacy signal handler for backward compatibility.
      Override this to handle old string-based signals during migration.
      """
      def handle_signal_legacy(_signal, state) do
        {:ok, state}
      end

      # Helper functions for common patterns

      @doc """
      Emit a typed message for routing.
      Skills should use MessageRouter.route() directly instead.
      """
      @deprecated "Use MessageRouter.route/1 instead"
      def emit_message(message) when is_struct(message) do
        Logger.warning("[#{@skill_name}] emit_message is deprecated. Use MessageRouter.route/1 directly.")
        RubberDuck.Routing.MessageRouter.route(message)
      end

      @doc """
      Gets skill metadata.
      """
      def skill_info do
        %{
          name: @skill_name,
          signal_patterns: @signal_patterns,
          supports_typed_messages: true,
          handlers: get_message_handlers()
        }
      end

      # Introspection helper
      defp get_message_handlers do
        functions = __MODULE__.__info__(:functions)

        functions
        |> Enum.filter(fn {name, arity} ->
          arity == 2 and String.starts_with?(Atom.to_string(name), "handle_")
        end)
        |> Enum.map(fn {name, _} -> name end)
      end

      # Make these overrideable
      defoverridable handle_message: 2,
                     handle_message_default: 2,
                     handle_signal_legacy: 2
    end
  end
end
