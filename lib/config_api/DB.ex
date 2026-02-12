defmodule ConfigApi.DB do
  def setup do
    Memento.Table.create!(ConfigApi.ConfigValue)
  end
end
