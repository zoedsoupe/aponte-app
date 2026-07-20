defmodule Aponte.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  # Captured at compile time — Mix isn't available at runtime in a release.
  # Workers run everywhere except test (periodic ticks are unwanted there).
  @start_workers Mix.env() != :test

  @impl true
  def start(_type, _args) do
    Aponte.Uploads.ensure_dirs!()
    Aponte.Editions.ensure_uploads_dir!()

    children =
      [
        AponteWeb.Telemetry,
        Aponte.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:aponte, :ecto_repos), skip: skip_migrations?()},
        {DNSCluster, query: Application.get_env(:aponte, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Aponte.PubSub},
        {Finch, name: Aponte.WebPush.Finch}
      ] ++ workers() ++ [AponteWeb.Endpoint]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Aponte.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AponteWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end

  defp workers do
    if @start_workers,
      do: [Aponte.Coupons.ExpiryWorker],
      else: []
  end
end
