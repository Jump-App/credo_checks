defmodule Mix.Tasks.JumpCredoChecks.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  @credo_config """
  %{
    configs: [
      %{
        name: "default",
        checks: %{
          enabled: [
            {Credo.Check.Consistency.ExceptionNames, []},
            {Credo.Check.Consistency.LineEndings, []}
          ],
          disabled: [
            {Credo.Check.Design.DuplicatedCode, []}
          ]
        }
      }
    ]
  }
  """

  @credo_config_with_jump """
  %{
    configs: [
      %{
        name: "default",
        checks: %{
          enabled: [
            {Credo.Check.Consistency.ExceptionNames, []},
            {Credo.Check.Consistency.LineEndings, []},
            {Jump.CredoChecks.AvoidFunctionLevelElse, []}
          ],
          disabled: [
            {Credo.Check.Design.DuplicatedCode, []}
          ]
        }
      }
    ]
  }
  """

  describe "igniter/1" do
    test "adds Jump checks to existing .credo.exs" do
      test_project(files: %{".credo.exs" => @credo_config})
      |> Igniter.compose_task("jump_credo_checks.install")
      |> assert_has_patch(".credo.exs", """
      + |{Jump.CredoChecks.AssertElementSelectorCanNeverFail, []},
      + |{Jump.CredoChecks.AssertReceiveTimeout, []},
      + |{Jump.CredoChecks.AvoidFunctionLevelElse, []},
      + |{Jump.CredoChecks.AvoidLoggerConfigureInTest, []},
      + |{Jump.CredoChecks.AvoidModifyingStructBeforeChangeset, []},
      + |{Jump.CredoChecks.AvoidSocketAssignsInTest, []},
      + |{Jump.CredoChecks.ConditionalAssertion, []},
      + |{Jump.CredoChecks.DoctestIExExamples, []},
      + |{Jump.CredoChecks.ForbiddenFunction, []},
      + |{Jump.CredoChecks.LiveViewFormCanBeRehydrated, []},
      + |{Jump.CredoChecks.LiveViewPubSubRequiresConnected, []},
      + |{Jump.CredoChecks.NoManualContentDisposition, []},
      + |{Jump.CredoChecks.PreferChangeOverUpDownMigrations, []},
      + |{Jump.CredoChecks.PreferTextColumns, []},
      + |{Jump.CredoChecks.SafeBinaryToTerm, []},
      + |{Jump.CredoChecks.TestHasNoAssertions, []},
      + |{Jump.CredoChecks.TooManyAssertions, []},
      + |{Jump.CredoChecks.TopLevelAliasImportRequire, []},
      + |{Jump.CredoChecks.UndeclaredExternalResource, []},
      + |{Jump.CredoChecks.UnusedLiveViewAssign, []},
      + |{Jump.CredoChecks.UseObanProWorker, []},
      + |{Jump.CredoChecks.VacuousTest, []},
      + |{Jump.CredoChecks.WeakAssertion, []}
      """)
    end

    test "adds every check defined in lib/jump/credo_checks" do
      checks = credo_checks_in_lib()
      assert length(checks) > 1, "Found no Credo checks in lib/jump/credo_checks; is the path wrong?"

      content =
        test_project(files: %{".credo.exs" => @credo_config})
        |> Igniter.compose_task("jump_credo_checks.install")
        |> Map.fetch!(:rewrite)
        |> Rewrite.source!(".credo.exs")
        |> Rewrite.Source.get(:content)

      missing = Enum.reject(checks, &String.contains?(content, "{#{inspect(&1)}, []}"))

      assert missing == [], """
      These checks exist in lib/jump/credo_checks but are not added by `mix jump_credo_checks.install`.
      Add them to @checks in lib/mix/tasks/jump_credo_checks.install.ex:

      #{Enum.map_join(missing, "\n", &inspect/1)}
      """
    end

    test "skips when Jump checks already present in .credo.exs" do
      test_project(files: %{".credo.exs" => @credo_config_with_jump})
      |> Igniter.compose_task("jump_credo_checks.install")
      |> assert_unchanged(".credo.exs")
    end

    test "warns when no .credo.exs exists" do
      test_project()
      |> Igniter.compose_task("jump_credo_checks.install")
      |> assert_has_warning(&String.contains?(&1, "No .credo.exs found"))
    end
  end

  defp credo_checks_in_lib do
    "../../../../lib/jump/credo_checks/*.ex"
    |> Path.expand(__DIR__)
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      ~r/^\s*defmodule\s+([\w.]+)/m
      |> Regex.scan(File.read!(path), capture: :all_but_first)
      |> List.flatten()
    end)
    |> Enum.map(&Module.concat([&1]))
    |> Enum.filter(&credo_check?/1)
  end

  # Check files may contain `defmodule` in their docs (e.g., example code), so
  # only keep modules that actually exist and implement Credo.Check
  defp credo_check?(module) do
    Code.ensure_loaded?(module) and
      Credo.Check in (module.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten())
  end
end
