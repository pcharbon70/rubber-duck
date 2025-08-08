defmodule RubberDuckWeb.Auth.DaisyUIOverrides do
  @moduledoc """
  DaisyUI-styled overrides for AshAuthentication.Phoenix components.
  """
  use AshAuthentication.Phoenix.Overrides
  alias AshAuthentication.Phoenix.Components

  override Components.Banner do
    set :image_class, "w-20 h-20 mx-auto"
    set :root_class, "text-center mb-8"
  end

  override Components.HorizontalRule do
    set :root_class, "divider"
  end

  override Components.Input do
    set :field_class, "input input-bordered w-full"
    set :label_class, "label"
    set :error_class, "label-text-alt text-error"
    set :input_class, "input input-bordered w-full"
  end

  override Components.Submit do
    set :button_class, "btn btn-primary w-full"
  end

  override Components.SignIn do
    set :root_class, "card bg-base-100 shadow-xl max-w-md mx-auto p-8"
  end
end