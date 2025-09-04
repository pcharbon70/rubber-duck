defmodule RubberDuck.Repo.Migrations.AddPromptSecurityFields do
  @moduledoc """
  Migration to add security and access control fields for Phase 02B Section 4.
  
  Adds fields for:
  - Approval workflows and status tracking
  - Security level classification
  - Access control policies  
  - Security validation timestamps
  - Audit trail support
  """
  
  use Ecto.Migration

  def change do
    # Add security fields to prompts table
    alter table(:prompts) do
      # Approval workflow fields
      add :approval_status, :string, default: "approved", null: false
      add :approval_required, :boolean, default: false, null: false
      add :approved_by, :uuid
      add :approved_at, :utc_datetime
      add :approval_comments, :text
      
      # Security classification fields
      add :security_level, :string, default: "standard", null: false
      add :risk_score, :decimal, precision: 3, scale: 2, default: 0.0
      add :last_security_check, :utc_datetime
      
      # Access control policy
      add :access_policy, :map, default: %{}
      
      # Security validation results
      add :security_validation_results, :map, default: %{}
      add :content_security_hash, :string
    end
    
    # Create audit logging table
    create table(:prompt_security_audits, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :prompt_id, references(:prompts, type: :uuid, on_delete: :cascade), null: false
      add :action, :string, null: false
      add :actor_id, :uuid
      add :actor_type, :string
      add :security_context, :map, default: %{}
      add :audit_metadata, :map, default: %{}
      add :severity, :string
      add :description, :text
      
      timestamps(type: :utc_datetime)
    end
    
    # Create indexes for performance
    create index(:prompts, [:approval_status])
    create index(:prompts, [:security_level])
    create index(:prompts, [:last_security_check])
    create index(:prompts, [:approval_required, :approval_status])
    
    create index(:prompt_security_audits, [:prompt_id])
    create index(:prompt_security_audits, [:action])
    create index(:prompt_security_audits, [:actor_id])
    create index(:prompt_security_audits, [:inserted_at])
    create index(:prompt_security_audits, [:severity])
    
    # Add check constraints for valid values
    create constraint(:prompts, :valid_approval_status, 
      check: "approval_status IN ('draft', 'pending', 'approved', 'rejected', 'expired')")
      
    create constraint(:prompts, :valid_security_level,
      check: "security_level IN ('minimal', 'standard', 'enhanced', 'maximum')")
      
    create constraint(:prompts, :valid_risk_score,
      check: "risk_score >= 0.0 AND risk_score <= 1.0")
      
    create constraint(:prompt_security_audits, :valid_severity,
      check: "severity IN ('info', 'warning', 'error', 'critical')")
  end
end