require 'dotenv'

# Custom error for missing variables
class UtcpVariableNotFound < StandardError
  attr_reader :variable_name

  def initialize(variable_name)
    @variable_name = variable_name
    super("Variable #{variable_name} referenced in provider configuration not found. " \
          "Please add it to the environment variables or to your UTCP configuration.")
  end
end

# Abstract base class for variable sources
class UtcpVariablesConfig
  attr_reader :type

  def initialize
    @type = 'dotenv' # mirrors Literal["dotenv"] default in Python
  end

  # Subclasses must implement this
  def get(key)
    raise NotImplementedError, "#{self.class} must implement #get"
  end
end

# Dotenv-backed implementation
class UtcpDotEnv < UtcpVariablesConfig
  def initialize(env_file_path:)
    super()
    @env_file_path = env_file_path
  end

  def get(key)
    return nil unless File.exist?(@env_file_path)

    # Parse .env file each time (similar to python dotenv_values behavior)
    env_hash = Dotenv.parse(@env_file_path)
    env_hash[key]
  rescue Errno::ENOENT
    nil
  end
end

# Client config container
class UtcpClientConfig
  attr_accessor :variables, :providers_file_path, :load_variables_from

  def initialize(variables: {}, providers_file_path: nil, load_variables_from: nil)
    @variables = stringify_keys(variables)
    @providers_file_path = providers_file_path
    if load_variables_from
      unless load_variables_from.all? { |v| v.is_a?(UtcpVariablesConfig) }
        raise ArgumentError, 'load_variables_from must be an array of UtcpVariablesConfig instances'
      end

      @load_variables_from = load_variables_from
    else
      @load_variables_from = []
    end
  end

  # Lookup order: explicit variables hash, custom sources, ENV, the
