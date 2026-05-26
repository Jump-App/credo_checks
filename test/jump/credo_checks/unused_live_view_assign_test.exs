defmodule Jump.CredoChecks.UnusedLiveViewAssignTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.UnusedLiveViewAssign

  test "accepts assigns read from HEEx" do
    """
    defmodule SampleLive do
      use SampleWeb, :live_view

      def render(assigns) do
        ~H\"\"\"
        {@name}
        \"\"\"
      end

      def mount(_params, _session, socket) do
        socket
        |> assign(:name, "Ada")
        |> ok()
      end
    end
    """
    |> to_source_file()
    |> run_check(UnusedLiveViewAssign)
    |> refute_issues()
  end

  @tag :tmp_dir
  test "accepts assigns read from a colocated HEEx template", %{tmp_dir: tmp_dir} do
    source_filename = Path.join(tmp_dir, "sample_live.ex")
    template_filename = Path.join(tmp_dir, "sample_live.html.heex")

    File.write!(template_filename, """
    {@name}
    """)

    """
    defmodule SampleLive do
      use SampleWeb, :live_view

      def mount(_params, _session, socket) do
        socket
        |> assign(:name, "Ada")
        |> ok()
      end
    end
    """
    |> to_source_file(source_filename)
    |> run_check(UnusedLiveViewAssign)
    |> refute_issues()
  end

  test "accepts assigns read from Elixir" do
    """
    defmodule SampleLive do
      use SampleWeb, :live_view

      def mount(_params, _session, socket) do
        socket
        |> assign(:name, "Ada")
        |> then(fn socket -> assign(socket, :name, socket.assigns.name) end)
      end
    end
    """
    |> to_source_file()
    |> run_check(UnusedLiveViewAssign)
    |> refute_issues()
  end

  test "accepts literal assigns read through map and access helpers" do
    """
    defmodule SampleLive do
      use SampleWeb, :live_view

      def mount(_params, _session, socket) do
        socket
        |> assign(:map_get, 123)
        |> assign(:access_by_module, 456)
        |> assign(:access_by_bracket, 789)
        |> tap(fn socket ->
          Map.get(socket.assigns, :map_get)
          Access.get(socket.assigns, :access_by_module)
          socket.assigns[:access_by_bracket]
        end)
      end
    end
    """
    |> to_source_file()
    |> run_check(UnusedLiveViewAssign)
    |> refute_issues()
  end

  test "accepts assigns read by pattern matching socket assigns" do
    """
    defmodule SampleLive do
      use SampleWeb, :live_view

      def mount(_params, _session, socket) do
        socket
        |> assign(:page, 1)
        |> then(fn socket ->
          %{page: page} = socket.assigns
          assign(socket, :page, page + 1)
        end)
      end
    end
    """
    |> to_source_file()
    |> run_check(UnusedLiveViewAssign)
    |> refute_issues()
  end

  test "accepts assigns read by helper function patterns" do
    """
    defmodule SampleLive do
      use SampleWeb, :live_view

      def mount(_params, _session, socket) do
        socket
        |> assign(:socket_pattern, 1)
        |> assign(:assigns_binding, 2)
        |> tap(fn socket ->
          read_from_socket(socket)
          read_from_assigns(socket.assigns)
        end)
      end

      defp read_from_socket(%{assigns: %{socket_pattern: socket_pattern}}) do
        socket_pattern
      end

      defp read_from_assigns(%{assigns_binding: assigns_binding} = _assigns) do
        assigns_binding
      end
    end
    """
    |> to_source_file()
    |> run_check(UnusedLiveViewAssign)
    |> refute_issues()
  end

  test "reports literal assigns that are never read" do
    """
    defmodule SampleLive do
      use SampleWeb, :live_view

      def render(assigns) do
        ~H\"\"\"
        {@name}
        \"\"\"
      end

      def mount(_params, _session, socket) do
        socket
        |> assign(:name, "Ada")
        |> assign(:unused_name, "Grace")
        |> ok()
      end
    end
    """
    |> to_source_file()
    |> run_check(UnusedLiveViewAssign)
    |> assert_issue(%{
      message: ~r/LiveView assign `:unused_name` is assigned/,
      trigger: ":unused_name",
      line_no: 13
    })
  end

  test "matches generic live view use wrappers" do
    """
    defmodule SampleLive do
      use MyAppWeb, :live_view

      def mount(_params, _session, socket) do
        assign(socket, :unused_name, "Ada")
      end
    end
    """
    |> to_source_file()
    |> run_check(UnusedLiveViewAssign)
    |> assert_issue(%{
      message: ~r/LiveView assign `:unused_name` is assigned/,
      trigger: ":unused_name",
      line_no: 5
    })
  end

  test "ignores page title by default" do
    """
    defmodule SampleLive do
      use SampleWeb, :live_view

      def mount(_params, _session, socket) do
        assign(socket, :page_title, "Title")
      end
    end
    """
    |> to_source_file()
    |> run_check(UnusedLiveViewAssign)
    |> refute_issues()
  end

  test "ignores configured assigns" do
    """
    defmodule SampleLive do
      use SampleWeb, :live_view

      def mount(_params, _session, socket) do
        assign(socket, :active_page, "max-w-xl")
      end
    end
    """
    |> to_source_file()
    |> run_check(UnusedLiveViewAssign, ignored_assigns: [:active_page])
    |> refute_issues()
  end

  test "reports keyword assigns that are never read" do
    """
    defmodule SampleLive do
      use SampleWeb, :live_view

      def render(assigns) do
        ~H\"\"\"
        {@name}
        \"\"\"
      end

      def mount(_params, _session, socket) do
        assign(socket, name: "Ada", unused_name: "Grace")
      end
    end
    """
    |> to_source_file()
    |> run_check(UnusedLiveViewAssign)
    |> assert_issue(%{
      message: ~r/LiveView assign `:unused_name` is assigned/,
      trigger: ":unused_name",
      line_no: 11
    })
  end

  test "does not treat keyword values in piped assign/3 as assign keys" do
    """
    defmodule SampleLive do
      use SampleWeb, :live_view

      def render(assigns) do
        ~H\"\"\"
        {@options[:good]}
        \"\"\"
      end

      def mount(_params, _session, socket) do
        socket
        |> assign(:options, good: "Good", bad: "Bad")
        |> ok()
      end
    end
    """
    |> to_source_file()
    |> run_check(UnusedLiveViewAssign)
    |> refute_issues()
  end

  test "ignores LiveView socket modules" do
    """
    defmodule SampleSocket do
      use Phoenix.LiveView.Socket

      def connect(_params, socket, _connect_info) do
        {:ok, assign(socket, :session_timeout_at, nil)}
      end
    end
    """
    |> to_source_file()
    |> run_check(UnusedLiveViewAssign)
    |> refute_issues()
  end

  test "accepts assign_async calls with opts" do
    """
    defmodule SampleLive do
      use SampleWeb, :live_view

      def render(assigns) do
        ~H\"\"\"
        {@user}
        \"\"\"
      end

      def mount(_params, _session, socket) do
        assign_async(socket, :user, fn -> {:ok, %{user: %{name: "Ada"}}} end, reset: true)
      end
    end
    """
    |> to_source_file()
    |> run_check(UnusedLiveViewAssign)
    |> refute_issues()
  end

  test "accepts streams read from HEEx" do
    """
    defmodule SampleLive do
      use SampleWeb, :live_view

      def render(assigns) do
        ~H\"\"\"
        <div :for={{id, item} <- @streams.items} id={id}>{item.name}</div>
        \"\"\"
      end

      def mount(_params, _session, socket) do
        stream(socket, :items, [])
      end
    end
    """
    |> to_source_file()
    |> run_check(UnusedLiveViewAssign)
    |> refute_issues()
  end
end
