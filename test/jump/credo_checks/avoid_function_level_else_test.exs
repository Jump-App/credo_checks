defmodule Jump.CredoChecks.AvoidFunctionLevelElseTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.AvoidFunctionLevelElse

  test "flags def with function-level else" do
    """
    defmodule Bad do
      def foo(bar) do
        something(bar)
      else
        {:error, reason} -> handle_error(reason)
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidFunctionLevelElse)
    |> assert_issue(fn issue ->
      assert issue.trigger == "def"
      assert issue.message =~ "Function-level `else`"
    end)
  end

  test "flags defp with function-level else" do
    """
    defmodule Bad do
      defp foo(bar) do
        something(bar)
      else
        {:error, reason} -> handle_error(reason)
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidFunctionLevelElse)
    |> assert_issue(fn issue ->
      assert issue.trigger == "defp"
    end)
  end

  test "flags def with rescue and else" do
    """
    defmodule Bad do
      def foo(bar) do
        something(bar)
      else
        {:error, reason} -> handle_error(reason)
      rescue
        e -> handle_exception(e)
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidFunctionLevelElse)
    |> assert_issue()
  end

  test "does not flag with/else inside a function" do
    """
    defmodule Good do
      def foo(bar) do
        with {:ok, result} <- something(bar) do
          result
        else
          {:error, reason} -> handle_error(reason)
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidFunctionLevelElse)
    |> refute_issues()
  end

  test "does not flag try/rescue inside a function" do
    """
    defmodule Good do
      def foo(bar) do
        try do
          something(bar)
        rescue
          e -> handle_exception(e)
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidFunctionLevelElse)
    |> refute_issues()
  end

  test "does not flag normal function without else" do
    """
    defmodule Good do
      def foo(bar) do
        something(bar)
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidFunctionLevelElse)
    |> refute_issues()
  end

  test "does not flag function with only rescue" do
    """
    defmodule Good do
      def foo(bar) do
        something(bar)
      rescue
        e -> handle_exception(e)
      end
    end
    """
    |> to_source_file()
    |> run_check(AvoidFunctionLevelElse)
    |> refute_issues()
  end
end
