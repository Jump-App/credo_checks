defmodule Jump.CredoChecks.PreferTextColumns do
  @moduledoc """
  Ensures that Ecto migrations use `:text` rather than `:string` for column types.

  In modern versions of Postgres, there is no storage or performance benefit
  to using textual columns with a fixed maximum length, so it is almost always preferable
  to not set a maximum length in the database and instead enforce max length as a business
  rule at the application level.

      # ❌ Bad
      def change do
        create table(:users) do
          add :name, :string
        end
      end

      # ✅ Good
      def change do
        create table(:users) do
          add :name, :text
        end
      end
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Ensures that Ecto migrations use `:text` rather than `:string` for column types.

      In modern versions of Postgres, there is no storage or performance benefit
      to using textual columns with a fixed maximum length, so it is almost always preferable
      to not set a maximum length in the database and instead enforce max length as a business
      rule at the application level.
      """
    ],
    param_defaults: [
      start_after: "0"
    ]

  def run(source_file, params) do
    start_after = Params.get(params, :start_after, __MODULE__)

    if relevant_file?(source_file.filename, start_after) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp traverse({op, meta, args} = ast, issues, issue_meta) when op in [:add, :modify] do
    if match?([_, :string | _], args) do
      issue = issue_for(issue_meta, meta[:line])
      {ast, [issue | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _), do: {ast, issues}

  defp issue_for(issue_meta, line_no) do
    format_issue(issue_meta,
      message: "Avoid using `:string` as a data type in migrations. Consider using `:text` instead.",
      trigger: ":string",
      line_no: line_no
    )
  end

  defp relevant_file?(path, start_after) do
    String.starts_with?(path, "priv") and String.contains?(path, "migrations") and
      migration_timestamp(path) > start_after
  end

  defp migration_timestamp(path) do
    path
    |> Path.basename()
    |> String.split("_")
    |> hd()
  end
end
