defmodule RubberDuck.Actions.Core.UpdateEntity.Executor do
  @moduledoc """
  Execution module for UpdateEntity action.

  Handles the actual application of changes to entities including:
  - Snapshot creation for rollback capability
  - Version management and tracking
  - Atomic change application
  - Update verification
  - Rollback and recovery operations
  """

  require Logger

  @doc """
  Main execution entry point that orchestrates the update process.

  Applies validated changes to the entity with proper versioning and verification.
  """
  def execute(params, context) do
    entity = params.entity || params.current_entity
    validated_changes = params.validated_changes || params.changes
    impact_assessment = Map.get(params, :impact_assessment, %{})

    with {:ok, snapshot} <- create_snapshot(entity),
         {:ok, versioned_entity} <- prepare_versioned_entity(entity, validated_changes),
         {:ok, updated_entity} <-
           apply_changes(versioned_entity, validated_changes, impact_assessment),
         {:ok, verification} <- verify_update(updated_entity, validated_changes),
         {:ok, finalized_entity} <- finalize_update(updated_entity, verification) do
      {:ok,
       %{
         entity: finalized_entity,
         previous_state: snapshot,
         verification: verification,
         version_info: extract_version_info(finalized_entity),
         execution_metadata: build_execution_metadata(params, context),
         rollback_info: build_rollback_info(snapshot, finalized_entity)
       }}
    else
      {:error, _reason} = error ->
        handle_execution_failure(error, params, context)
    end
  end

  @doc """
  Creates a snapshot of the entity for rollback capability.
  """
  def create_snapshot(entity) do
    snapshot = %{
      entity_id: entity[:id] || generate_id(),
      entity_type: entity[:type] || detect_entity_type(entity),
      snapshot_time: DateTime.utc_now(),
      data: deep_copy(entity),
      checksum: calculate_checksum(entity),
      version: entity[:version] || 1
    }

    {:ok, snapshot}
  rescue
    error ->
      Logger.error("Failed to create snapshot: #{inspect(error)}")
      {:error, {:snapshot_failed, error}}
  end

  defp generate_id do
    bytes = :crypto.strong_rand_bytes(16)
    bytes |> Base.encode16(case: :lower)
  end

  defp detect_entity_type(entity) do
    cond do
      Map.has_key?(entity, :email) -> :user
      Map.has_key?(entity, :project_id) -> :code_file
      Map.has_key?(entity, :owner_id) -> :project
      true -> :unknown
    end
  end

  defp deep_copy(%DateTime{} = dt), do: dt
  defp deep_copy(%Date{} = d), do: d
  defp deep_copy(%Time{} = t), do: t
  defp deep_copy(%NaiveDateTime{} = ndt), do: ndt
  defp deep_copy(entity) when is_struct(entity), do: entity

  defp deep_copy(entity) when is_map(entity) do
    Map.new(entity, fn {k, v} -> {k, deep_copy(v)} end)
  end

  defp deep_copy(entity) when is_list(entity) do
    Enum.map(entity, &deep_copy/1)
  end

  defp deep_copy(entity), do: entity

  defp calculate_checksum(entity) do
    entity
    |> :erlang.term_to_binary()
    |> then(fn binary -> :crypto.hash(:sha256, binary) end)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Prepares the entity with version information before applying changes.
  """
  def prepare_versioned_entity(entity, _validated_changes) do
    current_version = entity[:version] || 1

    versioned =
      entity
      |> Map.put(:version, current_version + 1)
      |> Map.put(:previous_version, current_version)
      |> Map.put(:version_timestamp, DateTime.utc_now())

    {:ok, versioned}
  end

  @doc """
  Applies the validated changes to the entity.
  """
  def apply_changes(entity, validated_changes, impact_assessment) do
    changes_map = extract_changes(validated_changes)

    updated =
      entity
      |> apply_field_changes(changes_map)
      |> apply_metadata_updates(validated_changes, impact_assessment)
      |> apply_computed_fields(changes_map)
      |> apply_timestamps()

    {:ok, updated}
  rescue
    error ->
      Logger.error("Failed to apply changes: #{inspect(error)}")
      {:error, {:apply_failed, error}}
  end

  defp extract_changes(%{changes: changes}) when is_map(changes), do: changes
  defp extract_changes(changes) when is_map(changes), do: changes
  defp extract_changes(_), do: %{}

  defp apply_field_changes(entity, changes) do
    Map.merge(entity, changes, fn _key, _old_val, new_val -> new_val end)
  end

  defp apply_metadata_updates(entity, validated_changes, impact_assessment) do
    metadata = entity[:metadata] || %{}

    updated_metadata =
      metadata
      |> Map.put(:last_update, DateTime.utc_now())
      |> Map.put(:change_count, count_changes(validated_changes))
      |> Map.put(:change_severity, get_severity(validated_changes))
      |> Map.put(:impact_score, impact_assessment[:impact_score] || 0)

    Map.put(entity, :metadata, updated_metadata)
  end

  defp count_changes(%{change_count: count}), do: count
  defp count_changes(%{changes: changes}) when is_map(changes), do: map_size(changes)
  defp count_changes(_), do: 0

  defp get_severity(%{change_severity: severity}), do: severity
  defp get_severity(_), do: :unknown

  defp apply_computed_fields(entity, changes) do
    entity
    |> compute_derived_fields(changes)
    |> update_relationships(changes)
    |> recalculate_aggregates(changes)
  end

  defp compute_derived_fields(entity, changes) do
    # Compute fields that depend on changed values
    cond do
      Map.has_key?(changes, :first_name) or Map.has_key?(changes, :last_name) ->
        full_name = "#{entity[:first_name]} #{entity[:last_name]}" |> String.trim()
        Map.put(entity, :full_name, full_name)

      Map.has_key?(changes, :price) or Map.has_key?(changes, :quantity) ->
        total = (entity[:price] || 0) * (entity[:quantity] || 0)
        Map.put(entity, :total, total)

      true ->
        entity
    end
  end

  defp update_relationships(entity, changes) do
    # Update relationship fields based on changes
    cond do
      Map.has_key?(changes, :parent_id) ->
        Map.put(entity, :relationship_updated_at, DateTime.utc_now())

      Map.has_key?(changes, :owner_id) ->
        Map.put(entity, :ownership_changed_at, DateTime.utc_now())

      true ->
        entity
    end
  end

  defp recalculate_aggregates(entity, _changes) do
    # Recalculate aggregate fields
    entity_type = entity[:type] || :unknown

    case entity_type do
      :project ->
        entity
        |> Map.put(:file_count, calculate_file_count(entity))
        |> Map.put(:total_size, calculate_total_size(entity))

      :user ->
        entity
        |> Map.put(:activity_score, calculate_activity_score(entity))

      _ ->
        entity
    end
  end

  defp calculate_file_count(entity) do
    length(entity[:files] || [])
  end

  defp calculate_total_size(entity) do
    (entity[:files] || [])
    |> Enum.map(&(&1[:size] || 0))
    |> Enum.sum()
  end

  defp calculate_activity_score(entity) do
    base_score = 0
    base_score = if entity[:last_login], do: base_score + 10, else: base_score
    base_score = if entity[:projects_count] > 0, do: base_score + 20, else: base_score
    base_score
  end

  defp apply_timestamps(entity) do
    now = DateTime.utc_now()

    entity
    |> Map.put(:updated_at, now)
    |> Map.put_new(:created_at, now)
  end

  @doc """
  Verifies that the update was applied successfully.
  """
  def verify_update(entity, validated_changes) do
    verifications = %{
      fields_updated: verify_fields_updated(entity, validated_changes),
      integrity_maintained: verify_data_integrity(entity),
      constraints_satisfied: verify_constraints_satisfied(entity, validated_changes),
      relationships_valid: verify_relationships(entity),
      version_consistent: verify_version_consistency(entity)
    }

    all_valid = verifications |> Map.values() |> Enum.all?(& &1)

    if all_valid do
      {:ok,
       %{
         verified: true,
         checks: verifications,
         entity_id: entity[:id],
         verification_time: DateTime.utc_now()
       }}
    else
      {:error,
       %{
         verified: false,
         checks: verifications,
         failed_checks: get_failed_checks(verifications)
       }}
    end
  end

  defp verify_fields_updated(entity, validated_changes) do
    changes = extract_changes(validated_changes)

    Enum.all?(changes, fn {field, expected_value} ->
      actual_value = Map.get(entity, field)
      values_match?(actual_value, expected_value)
    end)
  end

  defp values_match?(val1, val2) when is_float(val1) and is_float(val2) do
    abs(val1 - val2) < 0.0001
  end

  defp values_match?(val1, val2), do: val1 == val2

  defp verify_data_integrity(entity) do
    # Check that required fields are present and valid
    required_fields = get_required_fields(entity[:type])

    Enum.all?(required_fields, fn field ->
      value = Map.get(entity, field)
      not is_nil(value) and value != ""
    end)
  end

  defp get_required_fields(entity_type) do
    case entity_type do
      :user -> [:id, :email, :username]
      :project -> [:id, :name, :owner_id]
      :code_file -> [:id, :path, :project_id]
      _ -> [:id]
    end
  end

  defp verify_constraints_satisfied(_entity, validated_changes) do
    # Verify that all constraints from validation are still satisfied
    constraints =
      validated_changes[:validations][:constraint_validation][:constraints_checked] || 0

    violations = validated_changes[:validations][:constraint_validation][:violations] || []

    constraints == 0 or Enum.empty?(violations)
  end

  defp verify_relationships(entity) do
    # Verify that relationships are still valid
    entity_type = entity[:type] || :unknown

    case entity_type do
      :code_file ->
        # Verify project relationship
        not is_nil(entity[:project_id])

      :project ->
        # Verify owner relationship
        not is_nil(entity[:owner_id])

      _ ->
        true
    end
  end

  defp verify_version_consistency(entity) do
    current = entity[:version] || 1
    previous = entity[:previous_version] || 0

    current == previous + 1
  end

  defp get_failed_checks(verifications) do
    verifications
    |> Enum.filter(fn {_check, passed} -> not passed end)
    |> Enum.map(fn {check, _} -> check end)
  end

  @doc """
  Finalizes the update with any post-processing steps.
  """
  def finalize_update(entity, verification) do
    finalized =
      entity
      |> add_audit_trail(verification)
      |> clear_temporary_fields()
      |> compact_metadata()

    {:ok, finalized}
  end

  defp add_audit_trail(entity, verification) do
    audit_entry = %{
      timestamp: DateTime.utc_now(),
      action: :update,
      verified: verification.verified,
      version: entity[:version]
    }

    audit_trail = entity[:audit_trail] || []
    Map.put(entity, :audit_trail, [audit_entry | audit_trail])
  end

  defp clear_temporary_fields(entity) do
    entity
    |> Map.delete(:__temp__)
    |> Map.delete(:__processing__)
  end

  defp compact_metadata(entity) do
    case entity[:metadata] do
      nil ->
        entity

      metadata when is_map(metadata) ->
        compacted = Map.reject(metadata, fn {_k, v} -> is_nil(v) end)
        Map.put(entity, :metadata, compacted)

      _ ->
        entity
    end
  end

  @doc """
  Performs rollback of an entity to a previous snapshot.
  """
  def rollback(snapshot, current_entity) do
    with {:ok, validated_snapshot} <- validate_snapshot(snapshot),
         {:ok, restored_entity} <- restore_from_snapshot(validated_snapshot),
         {:ok, rollback_record} <- create_rollback_record(current_entity, restored_entity) do
      {:ok,
       %{
         entity: restored_entity,
         rollback_record: rollback_record,
         rolled_back_from: current_entity[:version],
         rolled_back_to: restored_entity[:version]
       }}
    end
  end

  defp validate_snapshot(snapshot) do
    checksum = calculate_checksum(snapshot.data)

    if checksum == snapshot.checksum do
      {:ok, snapshot}
    else
      {:error, :snapshot_corrupted}
    end
  end

  defp restore_from_snapshot(snapshot) do
    restored =
      snapshot.data
      |> Map.put(:restored_at, DateTime.utc_now())
      |> Map.put(:restored_from_snapshot, snapshot.snapshot_time)

    {:ok, restored}
  end

  defp create_rollback_record(from_entity, to_entity) do
    {:ok,
     %{
       rollback_time: DateTime.utc_now(),
       from_version: from_entity[:version],
       to_version: to_entity[:version],
       from_checksum: calculate_checksum(from_entity),
       to_checksum: calculate_checksum(to_entity)
     }}
  end

  @doc """
  Handles atomic batch updates for multiple changes.
  """
  def batch_execute(batch_params, context) do
    batch_id = generate_batch_id()

    results =
      batch_params
      |> Enum.map(fn params ->
        params
        |> Map.put(:batch_id, batch_id)
        |> execute(context)
      end)

    successful = Enum.filter(results, &match?({:ok, _}, &1))
    failed = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(failed) do
      {:ok,
       %{
         batch_id: batch_id,
         total: length(results),
         successful: length(successful),
         results: Enum.map(successful, fn {:ok, r} -> r end)
       }}
    else
      # Rollback all successful updates if any failed
      rollback_batch(successful)

      {:error,
       %{
         batch_id: batch_id,
         total: length(results),
         failed: length(failed),
         errors: Enum.map(failed, fn {:error, e} -> e end)
       }}
    end
  end

  defp generate_batch_id do
    bytes = :crypto.strong_rand_bytes(8)
    bytes |> Base.encode16(case: :lower)
  end

  defp rollback_batch(successful_results) do
    Enum.each(successful_results, fn {:ok, result} ->
      rollback(result.previous_state, result.entity)
    end)
  end

  defp extract_version_info(entity) do
    %{
      version: entity[:version] || 1,
      previous_version: entity[:previous_version] || 0,
      version_timestamp: entity[:version_timestamp] || entity[:updated_at]
    }
  end

  defp build_execution_metadata(params, context) do
    %{
      executed_at: DateTime.utc_now(),
      executor: context[:executor] || :system,
      execution_mode: (params[:batch_id] && :batch) || :single,
      batch_id: params[:batch_id]
    }
  end

  defp build_rollback_info(snapshot, entity) do
    %{
      can_rollback: true,
      snapshot_id: snapshot[:entity_id],
      snapshot_time: snapshot[:snapshot_time],
      current_version: entity[:version],
      snapshot_version: snapshot[:version]
    }
  end

  defp handle_execution_failure({:error, reason} = error, params, _context) do
    Logger.error("Execution failed: #{inspect(reason)}")

    if params[:rollback_on_failure] && params[:previous_state] do
      case rollback(params[:previous_state], params[:entity]) do
        {:ok, rollback_result} ->
          {:error, {:execution_failed_rolled_back, reason, rollback_result}}

        {:error, rollback_error} ->
          {:error, {:execution_failed_rollback_failed, reason, rollback_error}}
      end
    else
      error
    end
  end
end
