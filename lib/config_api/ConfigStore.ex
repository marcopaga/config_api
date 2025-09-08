defmodule ConfigApi.ConfigStore do
  alias ConfigApi.ConfigValue

  def get(name) do
    Memento.transaction! fn ->
      case Memento.Query.read(ConfigValue, name) do
        %ConfigValue{value: value} -> {:ok, value}
        nil -> {:error, :not_found}
      end
    end
  end

  def put(name, value) do
    # Get old value before update
    old_value = case get(name) do
      {:ok, val} -> val
      {:error, :not_found} -> nil
    end

    # Perform update in transaction
    Memento.transaction! fn ->
      %ConfigValue{name: name, value: value}
      |> Memento.Query.write()
    end

    # Notify worker (async, non-blocking)
    timestamp = DateTime.utc_now()
    send(:config_update_worker, {:config_updated, name, old_value, value, timestamp})

    {:ok, value}
  end

  def all do
    Memento.transaction! fn ->
      Memento.Query.all(ConfigValue)
      |> Enum.map(fn %ConfigValue{name: n, value: v} -> %{name: n, value: v} end)
    end
  end
end
