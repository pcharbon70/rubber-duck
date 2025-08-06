defmodule RubberDuck.Actions.Agent.CompleteInstruction do
  @moduledoc """
  Action for executing custom agent instructions.

  This action allows agents to handle custom instructions
  through the standard Jido action interface.
  """

  use Jido.Action,
    name: "complete_instruction",
    description: "Execute a custom agent instruction",
    schema: [
      instruction: [type: :any, required: true],
      agent_module: [type: :atom, required: true],
      agent_state: [type: :map, required: true]
    ]

  require Logger

  @impl true
  def run(params, _context) do
    case validate_instruction_params(params) do
      :ok ->
        instruction = params.instruction
        agent_module = params.agent_module
        agent_state = params.agent_state

        # Check if the agent module implements handle_instruction
        if function_exported?(agent_module, :handle_instruction, 2) do
          execute_agent_instruction(agent_module, instruction, agent_state)
        else
          {:error,
           %{
             reason: :handle_instruction_not_implemented,
             agent_module: agent_module,
             available_functions: get_exported_functions(agent_module)
           }}
        end

      {:error, reason} ->
        {:error, %{reason: reason, stage: :validation}}
    end
  rescue
    exception ->
      Logger.error(
        "Instruction execution crashed: #{inspect(exception)}\n#{Exception.format_stacktrace()}"
      )

      {:error,
       %{
         reason: {:exception, exception},
         message: Exception.message(exception),
         instruction: params.instruction
       }}
  end

  defp execute_agent_instruction(agent_module, instruction, agent_state) do
    case apply(agent_module, :handle_instruction, [instruction, %{state: agent_state}]) do
      {:ok, result, updated_agent} ->
        {:ok,
         %{
           result: result,
           state: updated_agent.state,
           instruction_type: elem(instruction, 0)
         }}

      {:ok, updated_agent} ->
        {:ok,
         %{
           state: updated_agent.state,
           instruction_type: elem(instruction, 0)
         }}

      {:error, reason} = error ->
        Logger.warning(
          "Instruction failed: #{inspect(reason)}, instruction: #{inspect(instruction)}"
        )

        error

      other ->
        Logger.error("Unexpected response from handle_instruction: #{inspect(other)}")
        {:error, %{reason: :unexpected_response, response: other}}
    end
  end

  defp validate_instruction_params(params) do
    cond do
      not is_map(params) ->
        {:error, :invalid_params}

      is_nil(params[:instruction]) ->
        {:error, :missing_instruction}

      not is_atom(params[:agent_module]) ->
        {:error, :invalid_agent_module}

      not is_map(params[:agent_state]) ->
        {:error, :invalid_agent_state}

      true ->
        :ok
    end
  end

  defp get_exported_functions(module) do
    :functions
    |> module.__info__()
    |> Enum.map(fn {name, arity} -> "#{name}/#{arity}" end)
    |> Enum.sort()
  rescue
    _ -> []
  end
end
