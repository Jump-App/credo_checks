defmodule Jump.CredoChecks.UseObanProWorkerTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.UseObanProWorker

  test "alerts on use of Oban.Worker" do
    """
    defmodule TestModule do
      use Oban.Worker
    end
    """
    |> to_source_file()
    |> run_check(UseObanProWorker)
    |> assert_issue()
  end

  test "alerts on use of Oban.Worker with options" do
    """
    defmodule TestModule do
      use Oban.Worker, queue: "default"
    end
    """
    |> to_source_file()
    |> run_check(UseObanProWorker)
    |> assert_issue()
  end

  test "alerts on multiple uses of Oban.Worker" do
    """
    defmodule TestModule do
      use Oban.Worker

      def perform(_job) do
        :ok
      end
    end

    defmodule AnotherModule do
      use Oban.Worker, queue: "high"
    end
    """
    |> to_source_file()
    |> run_check(UseObanProWorker)
    |> assert_issues()
  end

  test "does not alert on use of Oban.Pro.Worker" do
    """
    defmodule TestModule do
      use Oban.Pro.Worker
    end
    """
    |> to_source_file()
    |> run_check(UseObanProWorker)
    |> refute_issues()
  end

  test "does not alert on use of Oban.Pro.Worker with options" do
    """
    defmodule TestModule do
      use Oban.Pro.Worker, queue: "default"
    end
    """
    |> to_source_file()
    |> run_check(UseObanProWorker)
    |> refute_issues()
  end

  test "does not alert on other use statements" do
    """
    defmodule TestModule do
      use Phoenix.LiveView
      use Ecto.Schema
      use GenServer
    end
    """
    |> to_source_file()
    |> run_check(UseObanProWorker)
    |> refute_issues()
  end

  test "does not alert on non-use statements" do
    """
    defmodule TestModule do
      alias Oban.Worker
      import Oban.Worker
      require Oban.Worker
    end
    """
    |> to_source_file()
    |> run_check(UseObanProWorker)
    |> refute_issues()
  end

  test "alerts on nested use of Oban.Worker" do
    """
    defmodule TestModule do
      def some_function do
        if condition do
          use Oban.Worker
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(UseObanProWorker)
    |> assert_issue()
  end

  test "handles empty file" do
    ""
    |> to_source_file()
    |> run_check(UseObanProWorker)
    |> refute_issues()
  end

  test "handles file with only comments" do
    """
    # This is a comment
    # Another comment
    """
    |> to_source_file()
    |> run_check(UseObanProWorker)
    |> refute_issues()
  end

  test "alerts on use of Oban.Worker in complex module structure" do
    """
    defmodule TestModule do
      @moduledoc "Test module"

      use Oban.Worker, queue: "default"

      @callback perform(any()) :: :ok

      def perform(_job) do
        :ok
      end
    end
    """
    |> to_source_file()
    |> run_check(UseObanProWorker)
    |> assert_issue()
  end

  describe "string keys in args when args_schema is declared" do
    test "alerts on string-keyed args pattern in the process/1 head" do
      """
      defmodule MyApp.MyJob do
        use Oban.Pro.Worker, queue: :default, max_attempts: 5

        args_schema do
          field :service, :string, required: true
          field :record_id, :string, required: true
          field :meeting_id, :string, required: true
          field :user_id, :string
        end

        @impl Oban.Pro.Worker
        def process(%Oban.Job{args: %{"service" => service, "record_id" => record_id}}) do
          {service, record_id}
        end
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker)
      |> assert_issue(fn issue ->
        assert issue.line_no == 12
        assert issue.trigger =~ ~s("service")
        assert issue.message =~ "args_schema"
      end)
    end

    test "alerts when the job struct is aliased or matched as a plain map" do
      """
      defmodule MyApp.MyJob do
        use Oban.Pro.Worker
        alias Oban.Job

        args_schema do
          field :service, :string
        end

        def process(%Job{args: %{"service" => "a"}}), do: :a
        def process(%{args: %{"service" => "b"}}), do: :b
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker)
      |> assert_issues(fn issues ->
        assert Enum.map(issues, & &1.line_no) == [9, 10]
      end)
    end

    test "alerts on string-keyed args pattern bound to a variable or guarded" do
      """
      defmodule MyApp.MyJob do
        use Oban.Pro.Worker

        args_schema do
          field :count, :integer
        end

        def process(%Oban.Job{args: %{"count" => count} = args} = job) when count > 0 do
          {args, job}
        end

        def process(%Oban.Job{args: args = %{"count" => _}}), do: args
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker)
      |> assert_issues(fn issues ->
        assert Enum.map(issues, & &1.line_no) == [8, 12]
      end)
    end

    test "alerts on string-keyed matches against the args variable in the body" do
      """
      defmodule MyApp.MyJob do
        use Oban.Pro.Worker

        args_schema do
          field :service, :string
          field :record_id, :string
        end

        def process(%Oban.Job{args: args}) do
          %{"service" => service} = args
          record_id = args["record_id"]
          user_id = Map.get(args, "user_id")
          meeting_id = Map.fetch!(args, "meeting_id")
          {service, record_id, user_id, meeting_id}
        end
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker)
      |> assert_issues(fn issues ->
        assert Enum.map(issues, & &1.line_no) == [10, 11, 12, 13]
      end)
    end

    test "alerts on string-keyed access through the job variable" do
      """
      defmodule MyApp.MyJob do
        use Oban.Pro.Worker

        args_schema do
          field :service, :string
        end

        def process(job) do
          service = job.args["service"]
          args = job.args
          record_id = Map.get(args, "record_id")
          {service, record_id}
        end

        def process(%Oban.Job{} = job) do
          case job.args do
            %{"service" => service} -> service
            _ -> nil
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker)
      |> assert_issues(fn issues ->
        assert Enum.map(issues, & &1.line_no) == [9, 11, 17]
      end)
    end

    test "alerts on string-keyed patterns in with clauses" do
      """
      defmodule MyApp.MyJob do
        use Oban.Pro.Worker

        args_schema do
          field :service, :string
        end

        def process(%Oban.Job{args: args}) do
          with %{"service" => service} <- args do
            service
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker)
      |> assert_issue(fn issue ->
        assert issue.line_no == 9
      end)
    end

    test "does not alert on string keys when there is no args_schema" do
      """
      defmodule MyApp.MyJob do
        use Oban.Pro.Worker

        def process(%Oban.Job{args: %{"service" => service} = args}) do
          {service, args["record_id"], Map.get(args, "user_id")}
        end
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker)
      |> refute_issues()
    end

    test "does not alert on atom keys when args_schema is declared" do
      """
      defmodule MyApp.MyJob do
        use Oban.Pro.Worker

        args_schema do
          field :service, :string
          field :record_id, :string
        end

        def process(%Oban.Job{args: %{service: service, record_id: record_id} = args}) do
          {service, record_id, args[:user_id], Map.get(args, :meeting_id), args.service}
        end

        def process(%Oban.Job{args: %__MODULE__{service: service}}), do: service
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker)
      |> refute_issues()
    end

    test "does not alert on string keys nested inside an args field" do
      """
      defmodule MyApp.MyJob do
        use Oban.Pro.Worker

        args_schema do
          field :data, :map
        end

        def process(%Oban.Job{args: %{data: %{"office_id" => office_id} = data}}) do
          {office_id, data["notes"], Map.get(data, "notes")}
        end

        def process(%Oban.Job{args: args}) do
          %{data: data} = args
          %{"office_id" => office_id} = data
          office_id
        end
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker)
      |> refute_issues()
    end

    test "does not alert on string keys in other functions" do
      """
      defmodule MyApp.MyJob do
        use Oban.Pro.Worker

        args_schema do
          field :service, :string
        end

        def process(%Oban.Job{args: args}), do: helper(args)

        def new(%{"service" => service}), do: %{service: service}

        defp helper(%{"service" => service}), do: service
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker)
      |> refute_issues()
    end

    test "only considers args_schema declared in the same module" do
      """
      defmodule MyApp.Outer do
        use Oban.Pro.Worker

        defmodule Inner do
          use Oban.Pro.Worker

          args_schema do
            field :service, :string
          end

          def process(%Oban.Job{args: %{service: service}}), do: service
        end

        def process(%Oban.Job{args: %{"service" => service}}), do: service
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker)
      |> refute_issues()
    end

    test "alerts in a nested module that declares args_schema" do
      """
      defmodule MyApp.Outer do
        def process(%Oban.Job{args: %{"service" => service}}), do: service

        defmodule Inner do
          use Oban.Pro.Worker

          args_schema do
            field :service, :string
          end

          def process(%Oban.Job{args: %{"service" => service}}), do: service
        end
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker)
      |> assert_issue(fn issue ->
        assert issue.line_no == 11
      end)
    end

    test "does not alert on process/1 functions for non-Oban.Pro.Worker modules" do
      """
      defmodule MyApp.MyJob do
        import NotOban.Pro.Worker, only: [args_schema: 1]

        args_schema do
          field :service, :string
        end

        def process(%Oban.Job{args: %{"string_key" => val}}), do: val
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker)
      |> refute_issues()
    end
  end

  describe "supported_worker_modules" do
    @custom_only [supported_worker_modules: [MyCustomObanProWorker]]
    @pro_and_custom [supported_worker_modules: [Oban.Pro.Worker, MyCustomObanProWorker]]

    test "does not alert on use of a configured custom wrapper" do
      """
      defmodule TestModule do
        use MyCustomObanProWorker
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker, @custom_only)
      |> refute_issues()
    end

    test "still alerts on use of Oban.Worker when only a custom wrapper is supported" do
      """
      defmodule TestModule do
        use Oban.Worker
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker, @custom_only)
      |> assert_issue(fn issue ->
        assert issue.message =~ "MyCustomObanProWorker"
        assert issue.message =~ "Oban.Worker"
      end)
    end

    test "alerts on use of Oban.Pro.Worker when it is not in the supported list" do
      """
      defmodule TestModule do
        use Oban.Pro.Worker
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker, @custom_only)
      |> assert_issue(fn issue ->
        assert issue.message =~ "MyCustomObanProWorker"
        assert issue.message =~ "Oban.Pro.Worker"
      end)
    end

    test "does not alert on use of Oban.Pro.Worker when it remains in the supported list" do
      """
      defmodule TestModule do
        use Oban.Pro.Worker
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker, @pro_and_custom)
      |> refute_issues()
    end

    test "alerts on string-keyed args when the worker uses a configured custom wrapper" do
      """
      defmodule MyApp.MyJob do
        use MyCustomObanProWorker

        args_schema do
          field :service, :string, required: true
        end

        def process(%Oban.Job{args: %{"service" => service}}), do: service
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker, @custom_only)
      |> assert_issue(fn issue ->
        assert issue.line_no == 8
        assert issue.trigger =~ ~s("service")
        assert issue.message =~ "args_schema"
      end)
    end

    test "alerts when the custom wrapper is a nested module used with options" do
      """
      defmodule MyApp.MyJob do
        use MyApp.Workers.Base, queue: :default

        args_schema do
          field :service, :string
        end

        def process(%Oban.Job{args: %{"service" => service}}), do: service
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker, supported_worker_modules: [MyApp.Workers.Base])
      |> assert_issue(fn issue ->
        assert issue.line_no == 8
      end)
    end

    test "alerts for the matching module when multiple custom wrappers are configured" do
      """
      defmodule MyApp.MyJob do
        use AnotherProWorker

        args_schema do
          field :service, :string
        end

        def process(%Oban.Job{args: %{"service" => service}}), do: service
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker, supported_worker_modules: [MyCustomObanProWorker, AnotherProWorker])
      |> assert_issue()
    end

    test "does not alert on string keys for a custom wrapper that is not configured" do
      """
      defmodule MyApp.MyJob do
        use MyCustomObanProWorker

        args_schema do
          field :service, :string
        end

        def process(%Oban.Job{args: %{"service" => service}}), do: service
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker)
      |> refute_issues()
    end

    test "does not alert when a custom wrapper is used without args_schema" do
      """
      defmodule MyApp.MyJob do
        use MyCustomObanProWorker

        def process(%Oban.Job{args: %{"service" => service}}), do: service
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker, @custom_only)
      |> refute_issues()
    end

    test "does not alert on atom keys when a custom wrapper declares args_schema" do
      """
      defmodule MyApp.MyJob do
        use MyCustomObanProWorker

        args_schema do
          field :service, :string
        end

        def process(%Oban.Job{args: %{service: service}}), do: service
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker, @custom_only)
      |> refute_issues()
    end

    test "still checks string keys on Oban.Pro.Worker when it is included alongside custom modules" do
      """
      defmodule MyApp.MyJob do
        use Oban.Pro.Worker

        args_schema do
          field :service, :string
        end

        def process(%Oban.Job{args: %{"service" => service}}), do: service
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker, @pro_and_custom)
      |> assert_issue(fn issue ->
        assert issue.message =~ "args_schema"
      end)
    end

    test "does not check string keys on Oban.Pro.Worker when it is omitted from the supported list" do
      """
      defmodule MyApp.MyJob do
        use Oban.Pro.Worker

        args_schema do
          field :service, :string
        end

        def process(%Oban.Job{args: %{"service" => service}}), do: service
      end
      """
      |> to_source_file()
      |> run_check(UseObanProWorker, @custom_only)
      |> assert_issue(fn issue ->
        assert issue.line_no == 2
        assert issue.message =~ "Oban.Pro.Worker"
        refute issue.message =~ "args_schema"
      end)
    end

    test "does not alert when a supported wrapper module itself uses Oban" do
      for module <- [Oban.Pro.Worker, Oban.Worker] do
        """
        defmodule MyCustomObanProWorker do
          use #{module}, queue: :default

          defmacro __using__(opts) do
            quote do
              use #{module}, unquote(opts)
            end
          end
        end
        """
        |> to_source_file()
        |> run_check(UseObanProWorker, @custom_only)
        |> refute_issues()
      end
    end
  end
end
