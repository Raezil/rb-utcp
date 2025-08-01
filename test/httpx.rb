module HTTPX
  def self.plugin(*); self; end
  def self.with(timeout:); self; end
  def self.request(*); OpenStruct.new(status:200, to_s:'{}', headers:{}); end
  def self.post(*); OpenStruct.new(status:'200', to_s:'{}'); end
end
