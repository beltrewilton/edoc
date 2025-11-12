defmodule Edoc.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EdocWeb.Telemetry,
      Edoc.Repo,
      {DNSCluster, query: Application.get_env(:edoc, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Edoc.PubSub},
      {Finch, name: Edoc.Finch},
      # Start a worker by calling: Edoc.Worker.start_link(arg)
      # {Edoc.Worker, arg},
      # Start to serve requests, typically the last entry
      EdocWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Edoc.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EdocWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
