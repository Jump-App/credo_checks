defmodule Jump.CredoChecks.UseObanProWorker do
  @moduledoc """
  Ensures that Oban worker modules use the Oban.Pro.Worker module instead of Oban.Worker.
  """
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Ensures that Oban worker modules use the Oban.Pro.Worker module instead of Oban.Worker.

      If your project integrates Oban Pro at all, it's worth ensuring you always use the Pro
      worker so that you get all the Pro features.

          # ❌ Bad (misses Pro features)
          defmodule MyWorker do
            use Oban.Worker
          end

          # ✅ Good
          defmodule MyWorker do
            use Oban.Pro.Worker
          end
      """
    ]

  alias Credo.IssueMeta

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, &traverse_oban_worker(&1, &2, issue_meta))
  end

  defp traverse_oban_worker({:use, meta, [{:__aliases__, _, [:Oban, :Worker]} | _opts]} = ast, issues, issue_meta) do
    {ast, issues ++ [oban_worker_issue(issue_meta, Macro.to_string(ast), meta[:line])]}
  end

  defp traverse_oban_worker(ast, issues, _issue_meta), do: {ast, issues}

  defp oban_worker_issue(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message: "Use Oban.Pro.Worker instead of Oban.Worker for better safety and features.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
