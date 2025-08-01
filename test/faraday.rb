class Faraday
  def self.new(url:, &block)
    Class.new do
      def post(*); OpenStruct.new(status:200, body:'{}'); end
    end.new
  end
end
