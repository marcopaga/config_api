defmodule ConfigApi.ConfigValue do
  use Memento.Table,
    attributes: [:name, :value],
    type: :set,
    index: [],
    autoincrement: false
end
