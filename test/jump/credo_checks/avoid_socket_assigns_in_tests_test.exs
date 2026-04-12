defmodule Jump.CredoChecks.AvoidSocketAssignsInTestsTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.AvoidSocketAssignsInTest

  test "alerts on socket.assigns.foo" do
    """
    defmodule MyTest do
      use Jump.DataCase, async: true

      test "checks assigns" do
        assert socket.assigns.foo == :bar
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AvoidSocketAssignsInTest)
    |> assert_issue(fn issue ->
      assert issue.message =~ "socket.assigns"
    end)
  end

  test "alerts on result_socket.assigns.foo (non-socket var name)" do
    """
    defmodule MyTest do
      use Jump.DataCase, async: true

      test "checks assigns" do
        assert result_socket.assigns.foo == :bar
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AvoidSocketAssignsInTest)
    |> assert_issue(fn issue ->
      assert issue.message =~ "socket.assigns"
    end)
  end

  test "alerts on Map.has_key?(socket.assigns, :key)" do
    """
    defmodule MyTest do
      use Jump.DataCase, async: true

      test "checks assigns" do
        assert Map.has_key?(socket.assigns, :key)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AvoidSocketAssignsInTest)
    |> assert_issue(fn issue ->
      assert issue.message =~ "socket.assigns"
    end)
  end

  test "does not alert in non-test files" do
    """
    defmodule MyModule do
      def some_function(socket) do
        socket.assigns.foo
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidSocketAssignsInTest)
    |> refute_issues()
  end

  test "does not alert on conn.assigns" do
    """
    defmodule MyTest do
      use Jump.DataCase, async: true

      test "checks conn assigns" do
        assert conn.assigns.current_user
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AvoidSocketAssignsInTest)
    |> refute_issues()
  end

  test "does not alert with @moduletag :plug_test" do
    """
    defmodule MyTest do
      use Jump.DataCase, async: true

      @moduletag :plug_test

      test "checks assigns" do
        assert socket.assigns.foo == :bar
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AvoidSocketAssignsInTest)
    |> refute_issues()
  end

  test "does not alert with @tag :plug_test on specific test" do
    """
    defmodule MyTest do
      use Jump.DataCase, async: true

      @tag :plug_test
      test "checks assigns with plug_test tag" do
        assert socket.assigns.foo == :bar
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AvoidSocketAssignsInTest)
    |> refute_issues()
  end

  test "does not alert with @describetag :plug_test" do
    """
    defmodule MyTest do
      use Jump.DataCase, async: true

      describe "my describe" do
        @describetag :plug_test

        test "checks assigns" do
          assert socket.assigns.foo == :bar
        end
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AvoidSocketAssignsInTest)
    |> refute_issues()
  end

  test "still alerts outside @describetag :plug_test describe block" do
    """
    defmodule MyTest do
      use Jump.DataCase, async: true

      describe "tagged" do
        @describetag :plug_test

        test "this is fine" do
          assert socket.assigns.foo == :bar
        end
      end

      describe "not tagged" do
        test "this is not fine" do
          assert socket.assigns.foo == :bar
        end
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AvoidSocketAssignsInTest)
    |> assert_issue()
  end

  test "does not double-report var.assigns and var.assigns.field" do
    """
    defmodule MyTest do
      use Jump.DataCase, async: true

      test "checks assigns" do
        assert socket.assigns.foo == :bar
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(AvoidSocketAssignsInTest)
    |> assert_issue()
  end
end
