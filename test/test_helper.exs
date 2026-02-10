ExUnit.start()

# Ensure EventStore test database is initialized
case Mix.Task.run("event_store.init", ["--quiet"]) do
  :ok -> :ok
  {:error, _} -> :ok  # Already initialized
  _ -> :ok
end

# Start EventStore for tests
{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, _} = ConfigApi.EventStore.start_link()
