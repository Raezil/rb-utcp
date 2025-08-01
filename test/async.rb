module Async
  class Task
    def self.current; new; end
    def perform; yield; end
  end
  module HTTP
    class Internet
      def initialize(*); end
      def get(*); OpenStruct.new(status:200, read:'{"tools":[]}'); end
      def post(*); OpenStruct.new(status:200, read:'{}'); end
      def close; end
    end
  end
end
