# ConfigApi

This project exposes a simple config API. The configuration is saved within the
erlang vm using Memento.

## Run

```shell
iex -S mix
```

## Testing

```shell
➜  config_api git:(main) ✗ # 1. Liste aller Werte (sollte leer sein)
curl -i http://localhost:4000/config

# 2. Abfrage eines nicht existierenden Werts (404)
curl -i http://localhost:4000/config/foo

# 3. Einen Wert setzen (PUT)
curl -i -X PUT http://localhost:4000/config/foo \
     -H "Content-Type: application/json" \
     -d '{"value":"bar"}'

# 4. Den gerade gesetzten Wert abfragen (200, "bar")
curl -i http://localhost:4000/config/foobar

# 5. Einen zweiten Wert setzen
curl -i -X PUT http://localhost:4000/config/bar \
     -H "Content-Type: application/json" \
     -d '{"value":"qux"}'

# 6. Liste aller Werte (sollte beide enthalten, JSON)
curl -i http://localhost:4000/config
```

## Installation of erlang and elixir via ASDF
Erlang and Elixir are installed with ASDF.
