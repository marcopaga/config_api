ExUnit.start()

# Only initialize EventStore for integration tests
# Unit tests (run with --exclude integration) don't need database
unless "--exclude" in System.argv() and "integration" in System.argv() do
  # Ensure EventStore test database is initialized
  case Mix.Task.run("event_store.init", ["--quiet"]) do
    :ok -> :ok
    # Already initialized
    {:error, _} -> :ok
    _ -> :ok
  end

  # Start EventStore for tests (may already be started by application)
  {:ok, _} = Application.ensure_all_started(:postgrex)

  case ConfigApi.EventStore.start_link() do
    {:ok, _pid} -> :ok
    {:error, {:already_started, _pid}} -> :ok
  end
end
