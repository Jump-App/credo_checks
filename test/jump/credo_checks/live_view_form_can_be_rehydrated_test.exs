
defmodule Jump.CredoChecks.LiveViewFormCanBeRehydratedTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.LiveViewFormCanBeRehydrated

  test "reports issue for raw HTML form without id" do
    """
    defmodule TestLive do
      use Phoenix.Component

      def render(assigns) do
        ~H\"\"\"
        <form phx-submit="save">
          <input type="text" name="name" />
        </form>
        \"\"\"
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> assert_issue()
  end

  test "reports issue for component form without id" do
    """
    defmodule TestLive do
      use Phoenix.Component

      def render(assigns) do
        ~H\"\"\"
        <.form for={@form} phx-submit="save">
          <input type="text" name="name" />
        </.form>
        \"\"\"
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> assert_issue()
  end

  test "reports issue for Form.form without id" do
    """
    defmodule TestLive do
      use Phoenix.Component

      def render(assigns) do
        ~H\"\"\"
        <Form.form for={@form} phx-submit="save">
          <input type="text" name="name" />
        </Form.form>
        \"\"\"
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> assert_issue()
  end

  test "reports issue for PetalComponents.Form.form without id" do
    """
    defmodule TestLive do
      use Phoenix.Component

      def render(assigns) do
        ~H\"\"\"
        <PetalComponents.Form.form for={@form} phx-submit="save">
          <input type="text" name="name" />
        </PetalComponents.Form.form>
        \"\"\"
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> assert_issue()
  end

  test "does not report issue for raw HTML form with id" do
    """
    defmodule TestLive do
      use Phoenix.Component

      def render(assigns) do
        ~H\"\"\"
        <form id="user-form">
          <input type="text" name="name" />
        </form>
        \"\"\"
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> refute_issues()
  end

  test "does not report issue for component form with id and phx-change" do
    """
    defmodule TestLive do
      use Phoenix.Component

      def render(assigns) do
        ~H\"\"\"
        <.form
            id="user-form"
            for={@form}
            phx-submit="save"
            phx-change="validate"
        >
          <input type="text" name="name" />
        </.form>
        \"\"\"
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> refute_issues()
  end

  test "does not report issue for Form.form with id and phx-change" do
    """
    defmodule TestLive do
      use Phoenix.Component

      def render(assigns) do
        ~H\"\"\"
        <Form.form id="user-form" for={@form} phx-submit="save" phx-change="validate">
          <input type="text" name="name" />
        </Form.form>
        \"\"\"
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> refute_issues()
  end

  test "does not report issue for PetalComponents.Form.form with id and phx-change" do
    """
    defmodule TestLive do
      use Phoenix.Component

      def render(assigns) do
        ~H\"\"\"
        <PetalComponents.Form.form id="user-form" for={@form} phx-submit="save" phx-change="validate">
          <input type="text" name="name" />
        </PetalComponents.Form.form>
        \"\"\"
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> refute_issues()
  end

  test "handles form with id and phx-change using dynamic assigns" do
    """
    defmodule TestLive do
      use Phoenix.Component

      def render(assigns) do
        ~H\"\"\"
        <.form id={@form_id} for={@form} phx-submit="save" phx-change="validate">
          <input type="text" name="name" />
        </.form>
        \"\"\"
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> refute_issues()
  end

  test "handles multiple forms in same file" do
    """
    defmodule TestLive do
      use Phoenix.Component

      def render(assigns) do
        ~H\"\"\"
        <.form id="form-1" for={@form} phx-submit="save" phx-change="validate">
          <input type="text" name="name" />
        </.form>

        <form phx-submit="other">
          <input type="text" name="other" />
        </form>
        \"\"\"
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> assert_issue()
  end

  test "does not report issue for form without phx-submit" do
    """
    defmodule TestLive do
      use Phoenix.Component

      def render(assigns) do
        ~H\"\"\"
        <form>
          <input type="text" name="name" />
        </form>
        \"\"\"
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> refute_issues()
  end

  test "does not report issue for component form without phx-submit" do
    """
    defmodule TestLive do
      use Phoenix.Component

      def render(assigns) do
        ~H\"\"\"
        <.form for={@form}>
          <input type="text" name="name" />
        </.form>
        \"\"\"
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> refute_issues()
  end

  test "reports issue for form with phx-submit but missing phx-change" do
    """
    defmodule TestLive do
      use Phoenix.Component

      def render(assigns) do
        ~H\"\"\"
        <.form id="user-form" for={@form} phx-submit="save">
          <input type="text" name="name" />
        </.form>
        \"\"\"
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> assert_issue()
  end

  test "reports issue for form with phx-submit but missing id" do
    """
    defmodule TestLive do
      use Phoenix.Component

      def render(assigns) do
        ~H\"\"\"
        <.form for={@form} phx-submit="save" phx-change="validate">
          <input type="text" name="name" />
        </.form>
        \"\"\"
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> assert_issue()
  end

  test "reports issue for form with phx-submit but missing both id and phx-change" do
    """
    defmodule TestLive do
      use Phoenix.Component

      def render(assigns) do
        ~H\"\"\"
        <.form for={@form} phx-submit="save">
          <input type="text" name="name" />
        </.form>
        \"\"\"
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewFormCanBeRehydrated)
    |> assert_issue()
  end
end
