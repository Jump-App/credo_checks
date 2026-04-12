defmodule Jump.CredoChecks.AvoidLoggerConfigureInTest do
  @moduledoc """
  Modifying the global Logger config via `Logger.configure/1` can result in unwanted log messages from other tests.
  """
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      excluded: []
    ],
    explanations: [
      check: """
      Ensures that tests don't call `Logger.configure/1`.

      Calling `Logger.configure/1` in tests affects the global logger configuration
      for all concurrent test processes, which can introduce unexpected log spam
      and create flaky tests.

      Instead of trying to test for particular log messages, consider testing for
      results that indicate the right things happened. For example, the right
      database records were created, the expected side effects occurred, the function
      returned the expected value, etc.

      If the business outcome that goes along with the message can't be tested for,
      it's a code smell---you should consider refactoring the code to make it testable.
      """
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    # Only check test files
    if test_marked_async?(source_file) do
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp test_marked_async?(%SourceFile{} = source_file) do
    String.ends_with?(source_file.filename, "_test.exs") and test_marked_async?(Credo.SourceFile.ast(source_file))
  end

  defp test_marked_async?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {:use, _meta, [{:__aliases__, _, _module}, [async: true] | _]} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp traverse(node, issues, issue_meta) do
    case node do
      # Match Logger.configure/1 calls
      {{:., meta, [{:__aliases__, _, [:Logger]}, :configure]}, _, [_]} = ast ->
        {ast, issues ++ [create_issue(issue_meta, Macro.to_string(ast), meta[:line])]}

      _ ->
        {node, issues}
    end
  end

  defp create_issue(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "Instead of Logger.configure/1, test for business logic outcomes and side effects rather than log messages.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
