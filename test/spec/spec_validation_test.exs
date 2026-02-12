defmodule ConfigApi.Spec.SpecValidationTest do
  @moduledoc """
  Tests that validate the specification files themselves.

  These tests ensure that:
  - OpenAPI spec is valid YAML and has required fields
  - JSON schemas are valid
  - All file references exist
  - Examples are well-formed
  """
  use ExUnit.Case, async: true

  describe "OpenAPI specification validation" do
    test "main spec file exists and is valid YAML" do
      spec_path = "spec/openapi/configapi-v1.yaml"
      assert File.exists?(spec_path), "OpenAPI spec file should exist"

      # Parse YAML
      {:ok, spec} = YamlElixir.read_from_file(spec_path)

      # Validate root structure
      assert is_map(spec)
      assert Map.has_key?(spec, "openapi")
      assert spec["openapi"] == "3.1.0"
    end

    test "spec has required metadata fields" do
      {:ok, spec} = YamlElixir.read_from_file("spec/openapi/configapi-v1.yaml")

      # Info section
      assert Map.has_key?(spec, "info")
      assert Map.has_key?(spec["info"], "title")
      assert Map.has_key?(spec["info"], "version")
      assert Map.has_key?(spec["info"], "description")

      # Servers
      assert Map.has_key?(spec, "servers")
      assert is_list(spec["servers"])
      assert length(spec["servers"]) > 0

      # Paths
      assert Map.has_key?(spec, "paths")
      assert is_map(spec["paths"])
    end

    test "spec defines all expected v1 endpoints" do
      {:ok, spec} = YamlElixir.read_from_file("spec/openapi/configapi-v1.yaml")

      paths = spec["paths"]

      # Check all v1 endpoints are defined
      expected_paths = [
        "/v1/health",
        "/v1/config",
        "/v1/config/{name}",
        "/v1/config/{name}/history",
        "/v1/config/{name}/at/{timestamp}"
      ]

      Enum.each(expected_paths, fn path ->
        assert Map.has_key?(paths, path), "Path #{path} should be defined"
      end)
    end

    test "spec has components section with schemas" do
      {:ok, spec} = YamlElixir.read_from_file("spec/openapi/configapi-v1.yaml")

      assert Map.has_key?(spec, "components")
      assert Map.has_key?(spec["components"], "schemas")
      assert is_map(spec["components"]["schemas"])

      # Check expected schemas exist
      expected_schemas = [
        "SetConfigRequest",
        "HealthResponse",
        "ConfigListItem",
        "EventHistoryItem"
      ]

      Enum.each(expected_schemas, fn schema_name ->
        assert Map.has_key?(spec["components"]["schemas"], schema_name),
          "Schema #{schema_name} should be defined"
      end)
    end

    test "spec has CQRS custom extensions" do
      {:ok, spec} = YamlElixir.read_from_file("spec/openapi/configapi-v1.yaml")

      # Check for CQRS architecture extension
      assert Map.has_key?(spec, "x-cqrs-architecture")
      cqrs = spec["x-cqrs-architecture"]

      assert Map.has_key?(cqrs, "write-path")
      assert Map.has_key?(cqrs, "read-path")
      assert Map.has_key?(cqrs, "consistency")
    end
  end

  describe "Schema file validation" do
    test "all schema files exist" do
      schema_files = [
        "spec/openapi/schemas/requests.yaml",
        "spec/openapi/schemas/responses.yaml",
        "spec/openapi/schemas/errors.yaml",
        "spec/openapi/schemas/health.yaml"
      ]

      Enum.each(schema_files, fn file ->
        assert File.exists?(file), "Schema file #{file} should exist"
      end)
    end

    test "all schema files are valid YAML" do
      schema_files = [
        "spec/openapi/schemas/requests.yaml",
        "spec/openapi/schemas/responses.yaml",
        "spec/openapi/schemas/errors.yaml",
        "spec/openapi/schemas/health.yaml"
      ]

      Enum.each(schema_files, fn file ->
        {:ok, content} = YamlElixir.read_from_file(file)
        assert is_map(content), "#{file} should parse to a map"
      end)
    end

    test "requests.yaml defines SetConfigRequest" do
      {:ok, schemas} = YamlElixir.read_from_file("spec/openapi/schemas/requests.yaml")

      assert Map.has_key?(schemas, "SetConfigRequest")
      request_schema = schemas["SetConfigRequest"]

      assert request_schema["type"] == "object"
      assert "value" in request_schema["required"]
      assert Map.has_key?(request_schema["properties"], "value")
    end

    test "health.yaml defines HealthResponse" do
      {:ok, schemas} = YamlElixir.read_from_file("spec/openapi/schemas/health.yaml")

      assert Map.has_key?(schemas, "HealthResponse")
      health_schema = schemas["HealthResponse"]

      assert health_schema["type"] == "object"
      required = health_schema["required"]
      assert "status" in required
      assert "timestamp" in required
      assert "checks" in required
    end
  end

  describe "Path file validation" do
    test "all path files exist" do
      path_files = [
        "spec/openapi/paths/health.yaml",
        "spec/openapi/paths/config.yaml",
        "spec/openapi/paths/config-item.yaml",
        "spec/openapi/paths/history.yaml",
        "spec/openapi/paths/time-travel.yaml"
      ]

      Enum.each(path_files, fn file ->
        assert File.exists?(file), "Path file #{file} should exist"
      end)
    end

    test "path files are valid YAML" do
      path_files = [
        "spec/openapi/paths/health.yaml",
        "spec/openapi/paths/config.yaml",
        "spec/openapi/paths/config-item.yaml",
        "spec/openapi/paths/history.yaml",
        "spec/openapi/paths/time-travel.yaml"
      ]

      Enum.each(path_files, fn file ->
        {:ok, content} = YamlElixir.read_from_file(file)
        assert is_map(content), "#{file} should parse to a map"
      end)
    end

    test "config-item.yaml defines all three operations" do
      {:ok, path} = YamlElixir.read_from_file("spec/openapi/paths/config-item.yaml")

      # Should have GET, PUT, DELETE
      assert Map.has_key?(path, "get")
      assert Map.has_key?(path, "put")
      assert Map.has_key?(path, "delete")

      # Each should have required fields
      for operation <- ["get", "put", "delete"] do
        assert Map.has_key?(path[operation], "summary")
        assert Map.has_key?(path[operation], "description")
        assert Map.has_key?(path[operation], "responses")
      end
    end
  end

  describe "Parameter file validation" do
    test "parameters file exists and is valid" do
      assert File.exists?("spec/openapi/parameters/path.yaml")

      {:ok, params} = YamlElixir.read_from_file("spec/openapi/parameters/path.yaml")

      assert is_map(params)
      assert Map.has_key?(params, "ConfigName")
      assert Map.has_key?(params, "Timestamp")
    end

    test "ConfigName parameter is well-defined" do
      {:ok, params} = YamlElixir.read_from_file("spec/openapi/parameters/path.yaml")

      config_name = params["ConfigName"]
      assert config_name["name"] == "name"
      assert config_name["in"] == "path"
      assert config_name["required"] == true
      assert Map.has_key?(config_name, "schema")
    end

    test "Timestamp parameter is well-defined" do
      {:ok, params} = YamlElixir.read_from_file("spec/openapi/parameters/path.yaml")

      timestamp = params["Timestamp"]
      assert timestamp["name"] == "timestamp"
      assert timestamp["in"] == "path"
      assert timestamp["required"] == true
      assert Map.has_key?(timestamp, "schema")
      assert timestamp["schema"]["format"] == "date-time"
    end
  end

  describe "JSON Schema validation" do
    test "all event schema files exist" do
      schema_files = [
        "spec/json-schema/events/config-value-set.json",
        "spec/json-schema/events/config-value-deleted.json",
        "spec/json-schema/aggregates/config-value.json"
      ]

      Enum.each(schema_files, fn file ->
        assert File.exists?(file), "Schema file #{file} should exist"
      end)
    end

    test "JSON schemas are valid JSON" do
      schema_files = [
        "spec/json-schema/events/config-value-set.json",
        "spec/json-schema/events/config-value-deleted.json",
        "spec/json-schema/aggregates/config-value.json"
      ]

      Enum.each(schema_files, fn file ->
        {:ok, content} = File.read(file)
        {:ok, schema} = Jason.decode(content)
        assert is_map(schema), "#{file} should be a valid JSON object"
      end)
    end

    test "JSON schemas have correct $schema version" do
      schema_files = [
        "spec/json-schema/events/config-value-set.json",
        "spec/json-schema/events/config-value-deleted.json",
        "spec/json-schema/aggregates/config-value.json"
      ]

      Enum.each(schema_files, fn file ->
        {:ok, content} = File.read(file)
        {:ok, schema} = Jason.decode(content)

        assert Map.has_key?(schema, "$schema")
        # Using draft-07 for ex_json_schema compatibility
        assert schema["$schema"] == "http://json-schema.org/draft-07/schema#"
      end)
    end

    test "event schemas have required metadata" do
      event_schemas = [
        "spec/json-schema/events/config-value-set.json",
        "spec/json-schema/events/config-value-deleted.json"
      ]

      Enum.each(event_schemas, fn file ->
        {:ok, content} = File.read(file)
        {:ok, schema} = Jason.decode(content)

        # Validate metadata
        assert Map.has_key?(schema, "$id")
        assert Map.has_key?(schema, "title")
        assert Map.has_key?(schema, "description")
        assert Map.has_key?(schema, "type")
        assert schema["type"] == "object"

        # Validate custom extensions
        assert Map.has_key?(schema, "x-elixir-module")
        assert Map.has_key?(schema, "x-aggregate")
        assert schema["x-aggregate"] == "ConfigValue"
      end)
    end

    test "ConfigValueSet schema has correct required fields" do
      {:ok, content} = File.read("spec/json-schema/events/config-value-set.json")
      {:ok, schema} = Jason.decode(content)

      required = schema["required"]
      assert "config_name" in required
      assert "value" in required
      assert "timestamp" in required
      # old_value is optional
      refute "old_value" in required
    end

    test "ConfigValueDeleted schema has correct required fields" do
      {:ok, content} = File.read("spec/json-schema/events/config-value-deleted.json")
      {:ok, schema} = Jason.decode(content)

      required = schema["required"]
      assert "config_name" in required
      assert "deleted_value" in required
      assert "timestamp" in required
    end
  end

  describe "AsyncAPI specification validation" do
    test "AsyncAPI spec exists and is valid YAML" do
      spec_path = "spec/asyncapi/config-events-v1.yaml"
      assert File.exists?(spec_path)

      {:ok, spec} = YamlElixir.read_from_file(spec_path)

      assert is_map(spec)
      assert Map.has_key?(spec, "asyncapi")
      assert spec["asyncapi"] == "3.0.0"
    end

    test "AsyncAPI spec has required metadata" do
      {:ok, spec} = YamlElixir.read_from_file("spec/asyncapi/config-events-v1.yaml")

      # Info section
      assert Map.has_key?(spec, "info")
      assert Map.has_key?(spec["info"], "title")
      assert Map.has_key?(spec["info"], "version")

      # Channels
      assert Map.has_key?(spec, "channels")
      assert is_map(spec["channels"])
    end

    test "AsyncAPI spec defines event messages" do
      {:ok, spec} = YamlElixir.read_from_file("spec/asyncapi/config-events-v1.yaml")

      assert Map.has_key?(spec, "components")
      assert Map.has_key?(spec["components"], "messages")

      messages = spec["components"]["messages"]
      assert Map.has_key?(messages, "ConfigValueSet")
      assert Map.has_key?(messages, "ConfigValueDeleted")
    end
  end

  describe "Example file validation" do
    test "example files exist" do
      example_files = [
        "spec/openapi/examples/config-operations.yaml",
        "spec/openapi/examples/event-history.yaml"
      ]

      Enum.each(example_files, fn file ->
        assert File.exists?(file), "Example file #{file} should exist"
      end)
    end

    test "example files are valid YAML" do
      example_files = [
        "spec/openapi/examples/config-operations.yaml",
        "spec/openapi/examples/event-history.yaml"
      ]

      Enum.each(example_files, fn file ->
        {:ok, content} = YamlElixir.read_from_file(file)
        assert is_map(content), "#{file} should parse to a map"
      end)
    end
  end

  describe "Specification README" do
    test "README exists and is not empty" do
      readme_path = "spec/README.md"
      assert File.exists?(readme_path)

      content = File.read!(readme_path)
      assert String.length(content) > 100
      assert content =~ "ConfigApi Specifications"
    end
  end
end
