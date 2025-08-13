# lib/utcp/client.rb
# frozen_string_literal: true
require "json"
require "uri"
require_relative "errors"
require_relative "utils/env_loader"
require_relative "utils/subst"
require_relative "tool_repository"
require_relative "search"
require_relative "auth"
require_relative "providers/base_provider"
require_relative "providers/http_provider"
require_relative "providers/sse_provider"
require_relative "providers/http_stream_provider"
require_relative "providers/websocket_provider"
require_relative "providers/graphql_provider"
require_relative "providers/tcp_provider"
require_relative "providers/udp_provider"
require_relative "providers/cli_provider"
require_relative "providers/mcp_provider"

module Utcp
  class Client
    def self.create(config = {})
      new(config).tap(&:load_providers!)
    end

    def initialize(config = {})
      @config = config || {}
      @repo = ToolRepository.new
      env_files = Array(@config["load_variables_from"] || @config[:load_variables_from] || [".env"])
      env_files.each { |f| Utils::EnvLoader.load_file(f) }
    end

    attr_reader :repo

    def load_providers!
      path = @config["providers_file_path"] || @config[:providers_file_path]
      raise ConfigError, "providers_file_path required" unless path && File.file?(path)
      arr = JSON.parse(File.read(path))
      arr.each { |prov| register_manual_provider(prov) }
      self
    end

    def register_manual_provider(prov)
      name = prov["name"] || prov[:name] || "provider"
      type = (prov["provider_type"] || prov[:provider_type] || "http").downcase
      auth = Auth.from_hash(prov["auth"] || prov[:auth])

      tools = case type
      when "http"
        Providers::HttpProvider
          .new(name: name,
               url: prov["url"] || prov[:url],
               http_method: prov["http_method"] || prov[:http_method] || "GET",
               content_type: prov["content_type"] || "application/json",
               headers: prov["headers"] || {},
               manual: true,
               auth: auth)
          .discover_tools!
      when "mcp"
        Providers::McpProvider
          .new(name: name,
               url: prov["url"] || prov[:url],
               headers: prov["headers"] || {},
               auth: auth,
               manual: true,
               discovery_path: prov["discovery_path"] || "/manual")
          .discover_tools!
      when "text"
        manual_path = prov["file_path"] || prov[:file_path]
        raise ConfigError, "text provider missing file_path" unless manual_path && File.file?(manual_path)
        manual = JSON.parse(File.read(manual_path))
        to_tools(manual)
      else
        raise ConfigError, "Unsupported manual provider type: #{type}"
      end

      @repo.save_provider_with_tools(name, tools)
      tools
    end

    def call_tool(full_tool_name, arguments = {}, stream: false, &block)
      t = @repo.find(full_tool_name)
      p = t.provider || {}
      type = (p["provider_type"] || "http").downcase
      auth = Auth.from_hash(p["auth"])

      case type
      when "http"
        exec = Providers::HttpProvider.new(
          name: full_tool_name,
          url: p["url"],
          http_method: p["http_method"] || "GET",
          content_type: p["content_type"] || "application/json",
          headers: p["headers"] || {},
          manual: false,
          auth: auth,
          body_field: p["body_field"]
        )
        if stream
          raise ConfigError, "Streaming requires a block for HTTP" unless block_given?
          exec.call_tool(t, arguments, &block)
        else
          exec.call_tool(t, arguments)
        end

      when "sse"
        raise ConfigError, "Streaming requires a block for SSE" if stream && !block_given?
        exec = Providers::SseProvider.new(name: full_tool_name, auth: auth)
        exec.call_tool(t, arguments, &block)

      when "http_stream"
        raise ConfigError, "Streaming requires a block for http_stream" if stream && !block_given?
        exec = Providers::HttpStreamProvider.new(name: full_tool_name, auth: auth)
        exec.call_tool(t, arguments, &block)

      when "websocket"
        exec = Providers::WebSocketProvider.new(name: full_tool_name, auth: auth)
        exec.call_tool(t, arguments, &block)

      when "graphql"
        exec = Providers::GraphQLProvider.new(name: full_tool_name, auth: auth)
        exec.call_tool(t, arguments, &block)

      when "tcp"
        exec = Providers::TcpProvider.new(name: full_tool_name)
        exec.call_tool(t, arguments, &block)

      when "udp"
        exec = Providers::UdpProvider.new(name: full_tool_name)
        exec.call_tool(t, arguments, &block)

      when "cli"
        exec = Providers::CliProvider.new(name: full_tool_name)
        exec.call_tool(t, arguments, &block)

      when "mcp"
        exec = Providers::McpProvider.new(
          name: full_tool_name,
          url: p["url"],
          headers: p["headers"] || {},
          auth: auth
        )
        exec.call_tool(t, arguments, &block)

      else
        raise ConfigError, "Unsupported execution provider type: #{type}"
      end
    end

    def search_tools(query, limit: 5)
      Search.new(@repo).search(query, limit: limit)
    end

    private

    def to_tools(manual)
      (manual["tools"] || []).map do |t|
        Utcp::Tool.new(
          name: t["name"],
          description: t["description"],
          inputs: t["inputs"],
          outputs: t["outputs"],
          tags: t["tags"] || [],
          provider: t["tool_provider"] || {}
        )
      end
    end
  end
end
