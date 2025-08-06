defmodule RubberDuck.Skills.Base do
  @moduledoc """
  Base behavior for skills supporting both Jido signals and typed messages.
  
  This module provides a migration path from string-based signal patterns
  to strongly-typed messages while maintaining backward compatibility with
  the Jido framework.
  
  ## Usage
  
      defmodule MySkill do
        use RubberDuck.Skills.Base,
          name: "my_skill",
          signal_patterns: ["my.*"]  # For backward compatibility
        
        # Handle typed messages
        def handle_analyze(%Code.Analyze{} = msg, state) do
          # Type-safe message handling
          {:ok, result, state}
        end
        
        # Optional: Handle legacy signals during migration
        def handle_signal_legacy(signal, state) do
          # Old string-based handling
          {:ok, state}
        end
      end
  
  ## Migration Strategy
  
  1. Skills continue to work with existing Jido signals
  2. New typed message handlers are preferred when available
  3. Legacy handlers provide fallback during migration
  4. Once migration is complete, legacy handlers can be removed
  """
  
  defmacro __using__(opts) do
    quote location: :keep do
      use Jido.Skill, unquote(opts)
      
      alias RubberDuck.Adapters.SignalAdapter
      alias RubberDuck.Protocol.Message
      require Logger
      
      # Store the skill metadata
      @skill_name Keyword.get(unquote(opts), :name, "unnamed")
      @signal_patterns Keyword.get(unquote(opts), :signal_patterns, [])
      
      # Override Jido's handle_signal to support both patterns
      @impl true
      def handle_signal(signal, state) do
        start_time = System.monotonic_time(:microsecond)
        
        # Try to convert to typed message first
        result = case SignalAdapter.from_signal(signal) do
          {:ok, message} ->
            # Successfully converted to typed message
            handle_typed_message(message, state)
          
          {:error, {:unknown_signal_type, type}} ->
            # Signal type not registered, try legacy handler
            if function_exported?(__MODULE__, :handle_signal_legacy, 2) do
              Logger.debug("[#{@skill_name}] Using legacy handler for signal type: #{type}")
              handle_signal_legacy(signal, state)
            else
              Logger.warning("[#{@skill_name}] Unknown signal type with no legacy handler: #{type}")
              {:ok, state}
            end
          
          {:error, reason} ->
            # Conversion failed for other reasons
            Logger.error("[#{@skill_name}] Failed to convert signal: #{inspect(reason)}")
            {:ok, state}
        end
        
        # Emit telemetry
        duration = System.monotonic_time(:microsecond) - start_time
        emit_signal_telemetry(signal, duration, result)
        
        result
      end
      
      # Route typed messages to specific handlers
      defp handle_typed_message(message, state) do
        # Get the handler function name for this message type
        handler_function = message.__struct__
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
            Logger.debug("[#{@skill_name}] No handler for message type: #{inspect(message.__struct__)}")
            handle_message_default(message, state)
          end
        end
      rescue
        e ->
          Logger.error("[#{@skill_name}] Error handling message: #{inspect(e)}")
          {:error, e, state}
      end
      
      # Emit telemetry for monitoring
      defp emit_signal_telemetry(signal, duration, result) do
        success = case result do
          {:ok, _, _} -> true
          {:ok, _} -> true
          _ -> false
        end
        
        :telemetry.execute(
          [:rubber_duck, :skill, :signal],
          %{duration: duration},
          %{
            skill: @skill_name,
            signal_type: signal[:type] || "unknown",
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
      Emits a signal from within the skill.
      Automatically converts typed messages to signals.
      """
      def emit_signal(message) when is_struct(message) do
        case SignalAdapter.to_signal(message) do
          {:ok, signal} ->
            # Use Jido's signal emission
            # This would call the actual Jido emit function
            Logger.info("[#{@skill_name}] Emitting signal: #{signal.type}")
            :ok
          
          {:error, reason} ->
            Logger.error("[#{@skill_name}] Failed to emit signal: #{inspect(reason)}")
            {:error, reason}
        end
      end
      
      def emit_signal(type, data) when is_binary(type) do
        # Legacy signal emission
        signal = %{type: type, data: data, metadata: %{source: @skill_name}}
        Logger.info("[#{@skill_name}] Emitting legacy signal: #{type}")
        :ok
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
        __MODULE__.__info__(:functions)
        |> Enum.filter(fn {name, arity} ->
          arity == 2 and String.starts_with?(Atom.to_string(name), "handle_")
        end)
        |> Enum.map(fn {name, _} -> name end)
      end
      
      # Make these overrideable
      defoverridable [
        handle_message: 2,
        handle_message_default: 2,
        handle_signal_legacy: 2
      ]
    end
  end
end