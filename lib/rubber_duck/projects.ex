defmodule RubberDuck.Projects do
  @moduledoc """
  Domain for managing projects and code files in RubberDuck.

  Provides operations for creating, reading, updating, and deleting projects
  and their associated code files.
  """

  use Ash.Domain,
    otp_app: :rubber_duck

  resources do
    resource RubberDuck.Projects.Project do
      define :create_project, action: :create
      define :get_project, action: :read, get_by: [:id]
      define :list_projects, action: :read
      define :list_projects_by_owner, action: :by_owner
      define :list_active_projects, action: :active
      define :update_project, action: :update
      define :delete_project, action: :destroy
    end

    resource RubberDuck.Projects.CodeFile do
      define :create_code_file, action: :create
      define :get_code_file, action: :read, get_by: [:id]
      define :list_code_files, action: :read
      define :list_code_files_by_project, action: :by_project, args: [:project_id]
      define :list_active_code_files, action: :active
      define :update_code_file, action: :update
      define :delete_code_file, action: :destroy
    end
  end
end
