defmodule Jump.CredoChecks.AssertElementSelectorCanNeverFail do
  @moduledoc """
  Prevents mistakenly writing LiveViewTest assertions that can never fail.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Asserting on a LiveViewTest.element/{2,3} call can never fail, since when the selector
      has no results, the function returns the empty list.

      Instead, use LiveViewTest.has_element?{1,3}.
      """
    ]

  alias Credo.IssueMeta

  def run(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:assert, meta, [{:element, _, _} = element_call]} = ast, issues, issue_meta) do
    {ast, issues ++ [issue_for(issue_meta, Macro.to_string(element_call), meta[:line])]}
  end

  defp traverse(
         {:assert, meta, [{{:., _, [{:__aliases__, _, [:LiveViewTest]}, :element]}, _, _} = element_call]} = ast,
         issues,
         issue_meta
       ) do
    {ast, issues ++ [issue_for(issue_meta, Macro.to_string(element_call), meta[:line])]}
  end

  defp traverse(
         {:assert, meta, [{{:., _, [{:__aliases__, _, [:Phoenix, :LiveViewTest]}, :element]}, _, _} = element_call]} =
           ast,
         issues,
         issue_meta
       ) do
    {ast, issues ++ [issue_for(issue_meta, Macro.to_string(element_call), meta[:line])]}
  end

  defp traverse(ast, issues, _issue_meta) do
    {ast, issues}
  end

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message: "Direct assertion on element selector will always pass. Use has_element? instead.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
