defmodule RubberDuck.Preferences do
  @moduledoc """
  Preferences domain for hierarchical runtime configuration management.

  This domain provides a comprehensive preference system enabling:
  - System defaults with intelligent fallbacks
  - User-specific customization
  - Optional project-level overrides
  - Template-based configuration sharing
  - Complete audit trails and rollback capabilities
  - Secure handling of sensitive configuration data
  """

  use Ash.Domain

  resources do
    resource RubberDuck.Preferences.Resources.SystemDefault
    resource RubberDuck.Preferences.Resources.UserPreference
    resource RubberDuck.Preferences.Resources.ProjectPreference
    resource RubberDuck.Preferences.Resources.ProjectPreferenceEnabled
    resource RubberDuck.Preferences.Resources.PreferenceHistory
    resource RubberDuck.Preferences.Resources.PreferenceTemplate
    resource RubberDuck.Preferences.Resources.PreferenceValidation
    resource RubberDuck.Preferences.Resources.PreferenceCategory
  end

  authorization do
    authorize :when_requested
  end
end
