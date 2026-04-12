defmodule Jump.CredoChecks.AvoidLoggerConfigureInTestTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.AvoidLoggerConfigureInTest

  test "alerts on Logger.configure in test file" do
    """
    defmodule MyTest do
      use Jump.DataCase, async: true

      test "should not use Logger.configure" do
        Logger.configure(level: :debug)
        assert true
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AvoidLoggerConfigureInTest)
    |> assert_issue()
  end

  test "alerts on Logger.configure with keyword list in test file" do
    """
    defmodule MyTest do
      use Jump.DataCase, async: true

      test "should not configure logger" do
        Logger.configure([level: :error, truncate: 8096])
        assert true
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AvoidLoggerConfigureInTest)
    |> assert_issue()
  end

  test "alerts on Logger.configure with variable in test file" do
    """
    defmodule MyTest do
      use Jump.DataCase, async: true

      test "should not configure logger with variable" do
        config = [level: :info]
        Logger.configure(config)
        assert true
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AvoidLoggerConfigureInTest)
    |> assert_issue()
  end

  test "does not alert on Logger.configure in non-test files" do
    """
    defmodule MyModule do
      def configure_logging do
        Logger.configure(level: :debug)
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidLoggerConfigureInTest)
    |> refute_issues()
  end

  test "does not alert on other Logger functions in test files" do
    """
    defmodule MyTest do
      use Jump.DataCase, async: true

      test "allows other Logger functions" do
        Logger.info("This is fine")
        Logger.debug("This is also fine")
        Logger.error("This is acceptable")
        assert true
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AvoidLoggerConfigureInTest)
    |> refute_issues()
  end

  test "does not alert on Logger module attribute access in test files" do
    """
    defmodule MyTest do
      use Jump.DataCase, async: true

      test "allows Logger module references" do
        level = Logger.level()
        metadata = Logger.metadata()
        assert is_atom(level)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AvoidLoggerConfigureInTest)
    |> refute_issues()
  end
end
