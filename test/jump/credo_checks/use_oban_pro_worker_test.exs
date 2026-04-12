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
end
