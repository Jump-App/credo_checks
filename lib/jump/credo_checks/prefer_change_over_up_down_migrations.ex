defmodule Jump.CredoChecks.PreferChangeOverUpDownMigrations do
  @moduledoc """
  Ensures Ecto migrations take advantage of automatic reversibility where possible.

  Detects Ecto migrations that define `up` and `down` callbacks even though
  the `up` body is composed entirely of operations Ecto can automatically
  reverse. In that case, both callbacks can be replaced by a single `change` callback.

  For more information, see the [Ecto Migration docs](https://hexdocs.pm/ecto_sql/Ecto.Migration.html).
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Ensures Ecto migrations take advantage of automatic reversibility where possible.

      When every operation in an Ecto migration's `up` callback is one Ecto
      knows how to reverse (`create`/`alter` table, `create` index, `add` /
      `remove`-with-type / `modify`-with-`:from` columns, `rename`, etc.),
      a separate `down` callback is redundant and can be replaced by a
      single `change/0` callback.


          # ❌ Bad
          def up do
            alter table(:integration_schemas) do
              add :salesforce_record_types, :jsonb,
                null: false,
                default: fragment("'[]'::jsonb")
            end
          end

          def down do
            alter table(:integration_schemas) do
              remove :salesforce_record_types
            end
          end

          # ✅ Good
          def change do
            alter table(:integration_schemas) do
              add :salesforce_record_types, :jsonb,
                null: false,
                default: fragment("'[]'::jsonb")
            end
          end

      For more information, see the Ecto Migration docs:
      https://hexdocs.pm/ecto_sql/Ecto.Migration.html
      """
    ],
    param_defaults: [
      start_after: "0",
      excluded: []
    ]

  alias Credo.IssueMeta

  def run(source_file, params) do
    start_after = Params.get(params, :start_after, __MODULE__)
    excluded = Params.get(params, :excluded, __MODULE__)

    if relevant_file?(source_file.filename, start_after, excluded) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp traverse({:defmodule, _, [_alias, [do: body]]} = ast, issues, issue_meta) do
    statements = body_statements(body)
    up_def = Enum.find(statements, &up_def?/1)
    down_def = Enum.find(statements, &down_def?/1)

    if up_def && down_def && up_def |> def_body() |> reversible_block?() do
      {ast, [issue_for(issue_meta, def_line(up_def)) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp body_statements({:__block__, _, statements}), do: statements
  defp body_statements(nil), do: []
  defp body_statements(stmt), do: [stmt]

  defp up_def?({:def, _, [{:up, _, _} | _]}), do: true
  defp up_def?(_), do: false

  defp down_def?({:def, _, [{:down, _, _} | _]}), do: true
  defp down_def?(_), do: false

  defp def_body({:def, _, [_head, [do: body]]}), do: body
  defp def_body(_), do: nil

  defp def_line({:def, meta, _}), do: meta[:line]

  defp reversible_block?(nil), do: false

  defp reversible_block?(body) do
    body
    |> body_statements()
    |> Enum.all?(&reversible_statement?/1)
  end

  # `create table(:foo) do ... end` and `create_if_not_exists table(:foo) do ... end`
  defp reversible_statement?({create, _, [{:table, _, _}, [do: _]]}) when create in [:create, :create_if_not_exists],
    do: true

  # `create table(...)`, `create index(...)`, `create unique_index(...)`,
  # `create constraint(...)`, and the `create_if_not_exists` variants.
  defp reversible_statement?({create, _, [{call, _, _}]})
       when create in [:create, :create_if_not_exists] and call in [:table, :index, :unique_index, :constraint],
       do: true

  # `drop index(...)`, `drop unique_index(...)`, and the `drop_if_exists` variants.
  defp reversible_statement?({drop, _, [{call, _, _}]})
       when drop in [:drop, :drop_if_exists] and call in [:index, :unique_index], do: true

  defp reversible_statement?({drop, _, [{call, _, _}, opts]})
       when drop in [:drop, :drop_if_exists] and call in [:index, :unique_index] and is_list(opts), do: true

  # `alter table(:foo) do ... end` is reversible iff every inner op is.
  defp reversible_statement?({:alter, _, [{:table, _, _}, [do: body]]}) do
    body
    |> body_statements()
    |> Enum.all?(&reversible_alter_inner?/1)
  end

  # `rename table(:foo), to: table(:bar)`
  defp reversible_statement?({:rename, _, [{:table, _, _}, [to: {:table, _, _}]]}), do: true

  # `rename index(:foo, [:bar]), to: "new_index_name"`
  defp reversible_statement?({:rename, _, [{call, _, _}, [to: _new_name]]}) when call in [:index, :unique_index],
    do: true

  # `rename table(:foo), :col, to: :new_col`
  defp reversible_statement?({:rename, _, [{:table, _, _}, col, [to: new_col]]}) when is_atom(col) and is_atom(new_col),
    do: true

  # `execute(up_sql, down_sql)` and `execute_file(up_path, down_path)` use explicit reverse pairs.
  defp reversible_statement?({execute, _, args}) when execute in [:execute, :execute_file] and length(args) == 2,
    do: true

  defp reversible_statement?(_), do: false

  # Inside `alter table do ... end`:

  # `add :col, :type` and `add :col, :type, opts`
  defp reversible_alter_inner?({:add, _, args}) when length(args) in [2, 3], do: true

  # `remove :col, :type` and `remove :col, :type, opts` — needs the type to be reversible.
  defp reversible_alter_inner?({:remove, _, args}) when length(args) in [2, 3], do: true

  # `modify :col, :type, opts` — only reversible when opts include `:from`.
  defp reversible_alter_inner?({:modify, _, [_col, _type, opts]}) when is_list(opts) do
    not is_nil(Keyword.get(opts, :from))
  end

  # `timestamps()` expands to two `add` calls and is reversible.
  defp reversible_alter_inner?({:timestamps, _, _}), do: true

  defp reversible_alter_inner?(_), do: false

  defp issue_for(issue_meta, line_no) do
    format_issue(issue_meta,
      message:
        "This migration's `up` body is composed entirely of operations Ecto can reverse automatically; " <>
          "you can rename your `up` callback to `change/0` and delete `down` entirely.",
      trigger: "def up",
      line_no: line_no
    )
  end

  defp relevant_file?(path, start_after, excluded) do
    String.starts_with?(path, "priv") and String.contains?(path, "migrations") and
      migration_timestamp(path) > start_after and not String.contains?(path, excluded)
  end

  defp migration_timestamp(path) do
    path
    |> Path.basename()
    |> String.split("_")
    |> hd()
  end
end
