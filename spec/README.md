# ConfigApi Specifications

This directory contains machine-readable API specifications for ConfigApi.

## Overview

ConfigApi provides three types of specifications:

1. **OpenAPI 3.1**: REST API specification (`openapi/`)
2. **JSON Schema**: Domain event and aggregate schemas (`json-schema/`)
3. **AsyncAPI 3.0**: Event streaming specification (`asyncapi/`)

## Directory Structure

```
spec/
├── openapi/                          # OpenAPI 3.1 specification
│   ├── configapi-v1.yaml            # Main spec file
│   ├── schemas/                     # Request/response schemas
│   │   ├── requests.yaml
│   │   ├── responses.yaml
│   │   ├── errors.yaml
│   │   └── health.yaml
│   ├── paths/                       # Endpoint definitions
│   │   ├── config.yaml              # GET /v1/config
│   │   ├── config-item.yaml         # GET/PUT/DELETE /v1/config/:name
│   │   ├── history.yaml             # GET /v1/config/:name/history
│   │   ├── time-travel.yaml         # GET /v1/config/:name/at/:timestamp
│   │   └── health.yaml              # GET /v1/health
│   ├── parameters/
│   │   └── path.yaml                # Path parameters
│   └── examples/
│       ├── config-operations.yaml   # Request/response examples
│       └── event-history.yaml       # Event examples
├── json-schema/                      # JSON Schema 2020-12
│   ├── events/
│   │   ├── config-value-set.json    # ConfigValueSet event
│   │   └── config-value-deleted.json # ConfigValueDeleted event
│   └── aggregates/
│       └── config-value.json        # ConfigValue aggregate state
├── asyncapi/
│   └── config-events-v1.yaml        # AsyncAPI 3.0 spec
└── README.md                         # This file
```

## Using the OpenAPI Specification

### Validate the Specification

```bash
# Install Redocly CLI (if not installed)
npm install -g @redocly/cli

# Validate OpenAPI spec
npx @redocly/cli lint spec/openapi/configapi-v1.yaml
```

### Generate Interactive Documentation

#### Option 1: ReDoc (Static HTML)

```bash
# Generate standalone HTML file
npx @redocly/cli build-docs spec/openapi/configapi-v1.yaml -o docs/api-reference.html

# Open in browser
open docs/api-reference.html
```

#### Option 2: Swagger UI (Docker)

```bash
# Serve with Swagger UI
docker run -p 8080:8080 \
  -v $(pwd)/spec/openapi:/spec \
  -e SWAGGER_JSON=/spec/configapi-v1.yaml \
  swaggerapi/swagger-ui

# Open http://localhost:8080 in browser
```

#### Option 3: Local Development Server

```bash
# Using redoc-cli
npx redoc-cli serve spec/openapi/configapi-v1.yaml

# Open http://localhost:8080 in browser
```

### Use in API Clients

#### Generate Client Code

```bash
# Generate TypeScript client
npx @openapitools/openapi-generator-cli generate \
  -i spec/openapi/configapi-v1.yaml \
  -g typescript-fetch \
  -o clients/typescript

# Generate Python client
npx @openapitools/openapi-generator-cli generate \
  -i spec/openapi/configapi-v1.yaml \
  -g python \
  -o clients/python

# Generate Go client
npx @openapitools/openapi-generator-cli generate \
  -i spec/openapi/configapi-v1.yaml \
  -g go \
  -o clients/go
```

#### Import into Postman

1. Open Postman
2. Click "Import"
3. Select `spec/openapi/configapi-v1.yaml`
4. Postman will create a collection with all endpoints

#### Import into Insomnia

1. Open Insomnia
2. Click "Import/Export" → "Import Data" → "From File"
3. Select `spec/openapi/configapi-v1.yaml`
4. Insomnia will create a workspace with all endpoints

### Contract Testing

Run contract tests to verify the API implementation matches the specification:

```bash
# Run all contract tests
mix test test/spec/openapi_contract_test.exs

# Run event schema validation tests
mix test test/spec/event_schema_test.exs

# Run spec validation tests
mix test test/spec/spec_validation_test.exs

# Run all spec tests
mix test test/spec/
```

## Using JSON Schemas

### Validate Events

```elixir
# In iex
alias ConfigApi.Events.ConfigValueSet
alias ExJsonSchema.Validator

# Load schema
{:ok, schema} = File.read!("spec/json-schema/events/config-value-set.json") |> Jason.decode!()

# Create event
event = ConfigValueSet.new("api_key", "secret123", nil)

# Convert to map and validate
event_map = Map.from_struct(event)
ExJsonSchema.Validator.validate(schema, event_map)
# => :ok (if valid)
```

### Use in External Systems

JSON schemas can be used by external systems for:

- Event validation in message brokers
- Data pipelines and ETL processes
- Schema registries (e.g., Confluent Schema Registry)
- Documentation generation

## Using AsyncAPI Specification

### Validate AsyncAPI Spec

```bash
# Install AsyncAPI CLI
npm install -g @asyncapi/cli

# Validate spec
asyncapi validate spec/asyncapi/config-events-v1.yaml
```

### Generate Event Documentation

```bash
# Generate HTML documentation
asyncapi generate fromTemplate spec/asyncapi/config-events-v1.yaml @asyncapi/html-template -o docs/asyncapi

# Open documentation
open docs/asyncapi/index.html
```

### Generate Code from AsyncAPI

```bash
# Generate TypeScript types
asyncapi generate fromTemplate spec/asyncapi/config-events-v1.yaml @asyncapi/ts-nats-template -o clients/ts-events

# Generate Java client
asyncapi generate fromTemplate spec/asyncapi/config-events-v1.yaml @asyncapi/java-spring-cloud-stream-template -o clients/java-events
```

## API Versioning

ConfigApi uses URL path versioning:

- **Current version**: v1
- **Versioned routes**: All routes under `/v1/*`
- **Backward compatibility**: Unversioned routes (e.g., `/config`) are maintained temporarily

### Migration Guide

**From unversioned to v1:**

```bash
# Old (deprecated)
GET /config
GET /config/api_key
PUT /config/api_key

# New (recommended)
GET /v1/config
GET /v1/config/api_key
PUT /v1/config/api_key
```

**Timeline:**

- **v1.0**: Both versioned and unversioned routes work
- **v2.0**: Unversioned routes will be removed (deprecated)

## Extending the Specifications

### Adding a New Endpoint

1. **Create path definition** in `spec/openapi/paths/`
2. **Add schemas** if needed in `spec/openapi/schemas/`
3. **Reference from main spec** in `configapi-v1.yaml`
4. **Add examples** in `spec/openapi/examples/`
5. **Create contract tests** in `test/spec/openapi_contract_test.exs`
6. **Validate spec** with `npx @redocly/cli lint`
7. **Update documentation** in `docs/specifications/`

### Adding a New Event

1. **Create JSON schema** in `spec/json-schema/events/`
2. **Add to AsyncAPI** in `spec/asyncapi/config-events-v1.yaml`
3. **Create validation test** in `test/spec/event_schema_test.exs`
4. **Implement event** in `lib/config_api/events/`
5. **Update aggregate** to generate the event
6. **Update projection** to handle the event

### Modifying Existing Schemas

1. **Update schema files** in appropriate directory
2. **Run validation**: `npx @redocly/cli lint spec/openapi/configapi-v1.yaml`
3. **Update tests** to match new schema
4. **Run contract tests**: `mix test test/spec/`
5. **Regenerate documentation**
6. **Update examples** to reflect changes

## CI/CD Integration

The specification is validated in CI/CD pipeline:

```yaml
# .github/workflows/spec-validation.yml
- name: Validate OpenAPI spec
  run: npx @redocly/cli lint spec/openapi/configapi-v1.yaml

- name: Run contract tests
  run: mix test test/spec/

- name: Generate documentation
  run: npx @redocly/cli build-docs spec/openapi/configapi-v1.yaml
```

## Best Practices

1. **Keep specs in sync**: Update specifications when changing API
2. **Run contract tests**: Ensure implementation matches spec
3. **Use examples**: Provide comprehensive examples for all operations
4. **Validate before commit**: Run `npx @redocly/cli lint` before committing
5. **Document CQRS patterns**: Use custom `x-` extensions to document architecture
6. **Version breaking changes**: Use `/v2` prefix for breaking changes
7. **Update examples**: Keep curl and code examples current

## CQRS Architecture Documentation

The specifications include CQRS-specific annotations:

- **`x-cqrs-pattern`**: `command`, `query`, or `event`
- **`x-aggregate`**: Which aggregate handles the operation
- **`x-generates-event`**: Which event is generated
- **`x-read-from`**: Where queries read from (projection vs EventStore)
- **`x-consistency`**: Consistency model (immediate vs eventual)

These annotations help developers understand the CQRS/Event Sourcing architecture.

## Troubleshooting

### Spec validation fails

```bash
# Check for syntax errors
npx @redocly/cli lint spec/openapi/configapi-v1.yaml --format=stylish

# Check for broken references
npx @redocly/cli lint spec/openapi/configapi-v1.yaml --skip-rule=no-unused-components
```

### Contract tests fail

```bash
# Run with verbose output
mix test test/spec/openapi_contract_test.exs --trace

# Check if API implementation changed
mix test test/config_api_web/router_test.exs
```

### Documentation generation fails

```bash
# Try with different template
npx @redocly/cli build-docs spec/openapi/configapi-v1.yaml --template=classic

# Check Node.js version
node --version  # Should be >= 14
```

## Resources

- [OpenAPI 3.1 Specification](https://spec.openapis.org/oas/v3.1.0)
- [JSON Schema 2020-12](https://json-schema.org/draft/2020-12/json-schema-core.html)
- [AsyncAPI 3.0 Specification](https://www.asyncapi.com/docs/reference/specification/v3.0.0)
- [Redocly CLI Documentation](https://redocly.com/docs/cli/)
- [ConfigApi API Documentation](../docs/api/rest-api.md)
- [ConfigApi Architecture Guide](../docs/architecture/cqrs-implementation.md)

## Support

For questions about the specifications:

1. Check the [documentation](../docs/)
2. Review [examples](openapi/examples/)
3. Run contract tests to see expected behavior
4. Open an issue on GitHub
