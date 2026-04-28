if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.JumpCredoChecks.Install do
    @shortdoc "Install Jump.CredoChecks and configure .credo.exs"

    @moduledoc """
    Installs Jump.CredoChecks and adds all checks to your `.credo.exs` configuration.

    ## Recommended Installation

    ```bash
    mix igniter.install jump_credo_checks
    ```

    ## Manual Installation

    If you've already added jump_credo_checks to your dependencies:

    ```bash
    mix jump_credo_checks.install
    ```
    """

    use Igniter.Mix.Task

    alias Igniter.Mix.Task.Info
    alias Jump.CredoChecks.AssertElementSelectorCanNeverFail
    alias Jump.CredoChecks.AvoidFunctionLevelElse
    alias Jump.CredoChecks.AvoidLoggerConfigureInTest
    alias Jump.CredoChecks.AvoidSocketAssignsInTest
    alias Jump.CredoChecks.DoctestIExExamples
    alias Jump.CredoChecks.ForbiddenFunction
    alias Jump.CredoChecks.LiveViewFormCanBeRehydrated
    alias Jump.CredoChecks.PreferChangeOverUpDownMigrations
    alias Jump.CredoChecks.PreferTextColumns
    alias Jump.CredoChecks.TestHasNoAssertions
    alias Jump.CredoChecks.TooManyAssertions
    alias Jump.CredoChecks.TopLevelAliasImportRequire
    alias Jump.CredoChecks.UseObanProWorker
    alias Jump.CredoChecks.VacuousTest
    alias Jump.CredoChecks.WeakAssertion

    @checks [
      AssertElementSelectorCanNeverFail,
      AvoidFunctionLevelElse,
      AvoidLoggerConfigureInTest,
      AvoidSocketAssignsInTest,
      DoctestIExExamples,
      ForbiddenFunction,
      LiveViewFormCanBeRehydrated,
      PreferChangeOverUpDownMigrations,
      PreferTextColumns,
      TestHasNoAssertions,
      TooManyAssertions,
      TopLevelAliasImportRequire,
      UseObanProWorker,
      VacuousTest,
      WeakAssertion
    ]

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Info{
        group: :jump_credo_checks,
        example: "mix jump_credo_checks.install"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      credo_exs_path = ".credo.exs"

      if Igniter.exists?(igniter, credo_exs_path) do
        igniter
        |> Igniter.include_existing_file(credo_exs_path)
        |> add_checks_to_credo(credo_exs_path)
      else
        Igniter.add_warning(igniter, """
        No .credo.exs found. Generate one with `mix credo gen.config` and then
        re-run `mix jump_credo_checks.install` to add the checks automatically.

        Or manually add the following to your .credo.exs enabled checks:

        #{manual_checks_snippet()}
        """)
      end
    end

    defp add_checks_to_credo(igniter, path) do
      source = Rewrite.source!(igniter.rewrite, path)
      content = Rewrite.Source.get(source, :content)

      if String.contains?(content, "Jump.CredoChecks") do
        Igniter.add_notice(igniter, "Jump.CredoChecks are already configured in .credo.exs")
      else
        insert_checks(igniter, source, content)
      end
    end

    defp insert_checks(igniter, source, content) do
      checks_block = jump_checks_block()

      new_content =
        if String.contains?(content, "disabled:") do
          String.replace(
            content,
            ~r/(enabled:\s*\[.*?)((\s*\],\s*\n\s*disabled:))/s,
            "\\1,\n#{checks_block}\\2"
          )
        else
          String.replace(
            content,
            ~r/(enabled:\s*\[.*?)((\s*\]\s*\n\s*\}\s*\n))/s,
            "\\1,\n#{checks_block}\\2"
          )
        end

      if new_content == content do
        Igniter.add_warning(igniter, """
        Could not automatically add checks to .credo.exs.
        Please manually add the following to the enabled checks section:

        #{manual_checks_snippet()}
        """)
      else
        updated_source = Rewrite.Source.update(source, :content, new_content)
        %{igniter | rewrite: Rewrite.update!(igniter.rewrite, updated_source)}
      end
    end

    defp jump_checks_block do
      @checks
      |> Enum.map_join(",\n", fn check -> "            {#{inspect(check)}, []}" end)
    end

    defp manual_checks_snippet do
      @checks
      |> Enum.map_join(",\n", fn check -> "  {#{inspect(check)}, []}" end)
    end
  end
else
  defmodule Mix.Tasks.JumpCredoChecks.Install do
    @shortdoc "Install Jump.CredoChecks | Install `igniter` to use"

    @moduledoc """
    Installs Jump.CredoChecks and adds checks to your .credo.exs.
    Requires the `igniter` package.
    """

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'jump_credo_checks.install' requires igniter.
      Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
