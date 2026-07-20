defmodule Aponte.Repo do
  use Ecto.Repo,
    otp_app: :aponte,
    adapter: Ecto.Adapters.SQLite3
end
