defmodule Edoc.RequestLogger do
  @moduledoc """
  Appends each request as a single JSON line into
  /home/wilton/odoo-requests/YYYY-MM-DD.log (or LOG_DIR env).
  """

  @spec append(map()) :: :ok | {:error, term()}
  def append(map) when is_map(map) do
    dir = Application.get_env(:edoc, :log_dir, System.fetch_env!("LOG_DIR"))
    date = Date.utc_today() |> Date.to_iso8601()
    file = Path.join(dir, date <> ".log")

    with :ok <- File.mkdir_p(dir),
         {:ok, json} <- encode(map) do
      # Append atomically as best-effort; for extreme throughput consider a GenServer to serialize writes
      File.write(file, json <> "\n", [:append])
    end
  end

  defp encode(map) do
    try do
      {:ok, Jason.encode!(map)}
    rescue
      e -> {:error, e}
    end
  end
end
