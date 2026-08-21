defmodule Jump.CredoChecks.LiveViewPubSubRequiresConnectedTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.LiveViewPubSubRequiresConnected

  describe "flags PubSub calls in mount/3 without connected?" do
    test "aliased PubSub.subscribe" do
      """
      defmodule MyAppWeb.HomeLive do
        use MyAppWeb, {:live_view, admin: true}

        alias Phoenix.PubSub

        def mount(_params, _session, socket) do
          PubSub.subscribe("integrations:deleted")
          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> assert_issue(%{
        message: ~r/connected\?/,
        trigger: "PubSub.subscribe",
        line_no: 7
      })
    end

    test "fully-qualified Phoenix.PubSub.subscribe" do
      """
      defmodule MyAppWeb.HomeLive do
        def mount(_params, _session, socket) do
          Phoenix.PubSub.subscribe(MyApp.PubSub, "topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> assert_issue(%{
        trigger: "Phoenix.PubSub.subscribe",
        line_no: 3
      })
    end

    test "imported subscribe" do
      """
      defmodule MyAppWeb.HomeLive do
        import Phoenix.PubSub

        def mount(_params, _session, socket) do
          subscribe(MyApp.PubSub, "topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> assert_issue(%{trigger: "subscribe"})
    end

    test "alias Phoenix.{PubSub}" do
      """
      defmodule MyAppWeb.HomeLive do
        alias Phoenix.{PubSub}

        def mount(_params, _session, socket) do
          PubSub.subscribe(MyApp.PubSub, "topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> assert_issue(%{trigger: "PubSub.subscribe"})
    end

    test "alias with as:" do
      """
      defmodule MyAppWeb.HomeLive do
        alias Phoenix.PubSub, as: PS

        def mount(_params, _session, socket) do
          PS.subscribe(MyApp.PubSub, "topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> assert_issue(%{trigger: "PS.subscribe"})
    end

    test "multiple unguarded calls produce multiple issues" do
      """
      defmodule MyAppWeb.HomeLive do
        alias Phoenix.PubSub

        def mount(_params, _session, socket) do
          PubSub.subscribe("a")
          PubSub.subscribe("b")
          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> assert_issues(2)
    end

    test "subscribe in else of if connected?" do
      """
      defmodule MyAppWeb.HomeLive do
        alias Phoenix.PubSub

        def mount(_params, _session, socket) do
          if connected?(socket) do
            :ok
          else
            PubSub.subscribe("topic")
          end

          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> assert_issue()
    end

    test "connected? check that does not wrap the PubSub call" do
      """
      defmodule MyAppWeb.HomeLive do
        alias Phoenix.PubSub

        def mount(_params, _session, socket) do
          if connected?(socket) do
            :ok
          end

          PubSub.subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> assert_issue()
    end

    test "defp mount/3" do
      """
      defmodule MyAppWeb.HomeLive do
        alias Phoenix.PubSub

        defp mount(_params, _session, socket) do
          PubSub.subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> assert_issue()
    end

    test "piped PubSub call" do
      """
      defmodule MyAppWeb.HomeLive do
        def mount(_params, _session, socket) do
          "topic"
          |> Phoenix.PubSub.subscribe()

          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> assert_issue(%{trigger: "Phoenix.PubSub.subscribe"})
    end
  end

  describe "allows PubSub calls guarded by connected?" do
    test "if connected?(socket) do" do
      """
      defmodule MyAppWeb.HomeLive do
        use MyAppWeb, {:live_view, admin: true}

        alias Phoenix.PubSub

        def mount(_params, _session, socket) do
          if connected?(socket) do
            PubSub.subscribe("integrations:deleted")
          end

          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> refute_issues()
    end

    test "one-liner if connected?(socket), do:" do
      """
      defmodule MyAppWeb.HomeLive do
        alias Phoenix.PubSub

        def mount(_params, _session, socket) do
          if connected?(socket), do: PubSub.subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> refute_issues()
    end

    test "Phoenix.LiveView.connected?/1" do
      """
      defmodule MyAppWeb.HomeLive do
        def mount(_params, _session, socket) do
          if Phoenix.LiveView.connected?(socket) do
            Phoenix.PubSub.subscribe(MyApp.PubSub, "topic")
          end

          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> refute_issues()
    end

    test "if connected?(socket) && other" do
      """
      defmodule MyAppWeb.HomeLive do
        alias Phoenix.PubSub

        def mount(_params, _session, socket) do
          if connected?(socket) && socket.assigns.user do
            PubSub.subscribe("topic")
          end

          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> refute_issues()
    end

    test "unless not connected?(socket)" do
      """
      defmodule MyAppWeb.HomeLive do
        alias Phoenix.PubSub

        def mount(_params, _session, socket) do
          unless not connected?(socket) do
            PubSub.subscribe("topic")
          end

          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> refute_issues()
    end

    test "else of if not connected?(socket)" do
      """
      defmodule MyAppWeb.HomeLive do
        alias Phoenix.PubSub

        def mount(_params, _session, socket) do
          if not connected?(socket) do
            :ok
          else
            PubSub.subscribe("topic")
          end

          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> refute_issues()
    end

    test "else of unless connected?(socket)" do
      """
      defmodule MyAppWeb.HomeLive do
        alias Phoenix.PubSub

        def mount(_params, _session, socket) do
          unless connected?(socket) do
            :ok
          else
            PubSub.subscribe("topic")
          end

          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> refute_issues()
    end

    test "nested if inside connected? block" do
      """
      defmodule MyAppWeb.HomeLive do
        alias Phoenix.PubSub

        def mount(_params, _session, socket) do
          if connected?(socket) do
            if socket.assigns.user do
              PubSub.subscribe("topic")
            end
          end

          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> refute_issues()
    end
  end

  describe "ignores PubSub outside mount/3" do
    test "handle_info" do
      """
      defmodule MyAppWeb.HomeLive do
        alias Phoenix.PubSub

        def mount(_params, _session, socket) do
          {:ok, socket}
        end

        def handle_info(:resubscribe, socket) do
          PubSub.subscribe("topic")
          {:noreply, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> refute_issues()
    end

    test "mount/1 (not LiveView mount/3)" do
      """
      defmodule MyAppWeb.SomeComponent do
        alias Phoenix.PubSub

        def mount(socket) do
          PubSub.subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> refute_issues()
    end

    test "unrelated subscribe without Phoenix.PubSub import" do
      """
      defmodule MyAppWeb.HomeLive do
        def mount(_params, _session, socket) do
          subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> refute_issues()
    end

    test "no PubSub in mount" do
      """
      defmodule MyAppWeb.HomeLive do
        def mount(_params, _session, socket) do
          {:ok, assign(socket, :page, :home)}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> refute_issues()
    end

    test "custom wrapper is ignored unless configured" do
      """
      defmodule MyAppWeb.HomeLive do
        def mount(_params, _session, socket) do
          MyAppWeb.PubSub.subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected)
      |> refute_issues()
    end
  end

  describe "custom_pubsub_functions" do
    test "flags configured wrapper module call" do
      """
      defmodule MyAppWeb.HomeLive do
        def mount(_params, _session, socket) do
          MyAppWeb.PubSub.subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected, custom_pubsub_functions: [{MyAppWeb.PubSub, :subscribe}])
      |> assert_issue(%{trigger: "MyAppWeb.PubSub.subscribe"})
    end

    test "flags aliased wrapper module call" do
      """
      defmodule MyAppWeb.HomeLive do
        alias MyAppWeb.PubSub

        def mount(_params, _session, socket) do
          PubSub.subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected, custom_pubsub_functions: [{MyAppWeb.PubSub, :subscribe}])
      |> assert_issue(%{trigger: "PubSub.subscribe"})
    end

    test "flags imported wrapper call" do
      """
      defmodule MyAppWeb.HomeLive do
        import MyAppWeb.PubSub

        def mount(_params, _session, socket) do
          subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected, custom_pubsub_functions: [{MyAppWeb.PubSub, :subscribe}])
      |> assert_issue(%{trigger: "subscribe"})
    end

    test "flags local wrapper by function and arity" do
      """
      defmodule MyAppWeb.HomeLive do
        def mount(_params, _session, socket) do
          subscribe_user_events(socket)
          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected, custom_pubsub_functions: [{:subscribe_user_events, 1}])
      |> assert_issue(%{trigger: "subscribe_user_events"})
    end

    test "allows configured wrapper when guarded by connected?" do
      """
      defmodule MyAppWeb.HomeLive do
        def mount(_params, _session, socket) do
          if connected?(socket) do
            MyAppWeb.PubSub.subscribe("topic")
          end

          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected, custom_pubsub_functions: [{MyAppWeb.PubSub, :subscribe}])
      |> refute_issues()
    end

    test "does not flag other functions on the wrapper module" do
      """
      defmodule MyAppWeb.HomeLive do
        def mount(_params, _session, socket) do
          MyAppWeb.PubSub.node_name()
          {:ok, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(LiveViewPubSubRequiresConnected, custom_pubsub_functions: [{MyAppWeb.PubSub, :subscribe}])
      |> refute_issues()
    end
  end
end
