# Basic client configuration container.
class UtcpClientConfig
  attr_accessor :variables, :providers_file_path, :load_variables_from

  def initialize(variables: {}, providers_file_path: nil, load_variables_from: [])
    @variables = variables || {}
    @providers_file_path = providers_file_path
    @load_variables_from = load_variables_from || []
  end

  def self.model_validate(hash)
    new(**hash.transform_keys(&:to_sym))
  end
end
