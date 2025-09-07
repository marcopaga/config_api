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
    Memento.transaction! fn ->
      %ConfigValue{name: name, value: value}
      |> Memento.Query.write()
    end
    {:ok, value}
  end

  def all do
    Memento.transaction! fn ->
      Memento.Query.all(ConfigValue)
      |> Enum.map(fn %ConfigValue{name: n, value: v} -> %{name: n, value: v} end)
    end
  end
end
