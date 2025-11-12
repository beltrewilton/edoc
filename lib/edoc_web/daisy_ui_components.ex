defmodule EdocWeb.DaisyUIComponents do
  @doc false
  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(helpers())
    end
  end

  @doc false
  def component do
    quote do
      use Phoenix.Component

      unquote(helpers())
    end
  end

  defp helpers() do
    quote do
      import EdocWeb.DaisyUIComponents.Utils
      import EdocWeb.DaisyUIComponents.JSHelpers

      alias Phoenix.LiveView.JS
    end
  end

  @doc """
  Used for functional or live components
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end

  defmacro __using__(opts) do
    core_components = Keyword.get(opts, :core_components, true)

    quote do
      unquote(
        if core_components do
          quote do
            import EdocWeb.DaisyUIComponents.Button
            import EdocWeb.DaisyUIComponents.Flash
            import EdocWeb.DaisyUIComponents.Form
            import EdocWeb.DaisyUIComponents.Icon
            import EdocWeb.DaisyUIComponents.Header
            import EdocWeb.DaisyUIComponents.Input
            import EdocWeb.DaisyUIComponents.JSHelpers
            import EdocWeb.DaisyUIComponents.List
            import EdocWeb.DaisyUIComponents.Table
          end
        end
      )

      import EdocWeb.DaisyUIComponents.Accordion
      import EdocWeb.DaisyUIComponents.Alert
      import EdocWeb.DaisyUIComponents.Avatar
      import EdocWeb.DaisyUIComponents.Back
      import EdocWeb.DaisyUIComponents.Badge
      import EdocWeb.DaisyUIComponents.Breadcrumbs
      import EdocWeb.DaisyUIComponents.Card
      import EdocWeb.DaisyUIComponents.Checkbox
      import EdocWeb.DaisyUIComponents.Collapse
      import EdocWeb.DaisyUIComponents.Drawer
      import EdocWeb.DaisyUIComponents.Dropdown
      import EdocWeb.DaisyUIComponents.Fieldset
      import EdocWeb.DaisyUIComponents.Footer
      import EdocWeb.DaisyUIComponents.Hero
      import EdocWeb.DaisyUIComponents.Indicator
      import EdocWeb.DaisyUIComponents.Join
      import EdocWeb.DaisyUIComponents.Label
      import EdocWeb.DaisyUIComponents.Loading
      import EdocWeb.DaisyUIComponents.Menu
      import EdocWeb.DaisyUIComponents.Modal
      import EdocWeb.DaisyUIComponents.Navbar
      import EdocWeb.DaisyUIComponents.Pagination
      import EdocWeb.DaisyUIComponents.Progress
      import EdocWeb.DaisyUIComponents.Radio
      import EdocWeb.DaisyUIComponents.Range
      import EdocWeb.DaisyUIComponents.Select
      import EdocWeb.DaisyUIComponents.Sidebar
      import EdocWeb.DaisyUIComponents.Stat
      import EdocWeb.DaisyUIComponents.Swap
      import EdocWeb.DaisyUIComponents.Tabs
      import EdocWeb.DaisyUIComponents.TextInput
      import EdocWeb.DaisyUIComponents.Textarea
      import EdocWeb.DaisyUIComponents.Toggle
      import EdocWeb.DaisyUIComponents.Tooltip
    end
  end
end
