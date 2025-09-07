defmodule ConfigApiTest do
  use ExUnit.Case
  doctest ConfigApi

  test "greets the world" do
    assert ConfigApi.hello() == :world
  end
end
