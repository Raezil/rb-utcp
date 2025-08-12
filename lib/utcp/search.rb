# frozen_string_literal: true
module Utcp
  class Search
    def initialize(repo)
      @repo = repo
    end

    # returns [ [score, tool_full_name], ... ] sorted desc
    def search(query, limit: 5)
      q = query.to_s.downcase
      scores = []
      @repo.all_tools.each do |t|
        text = [t.name, t.description, (t.tags || []).join(" ")].join(" ").downcase
        score = 0
        q.split.each { |w| score += 3 if text.include?(w) }
        scores << [score, t]
      end
      scores.select { |s, _| s > 0 }.sort_by { |s, _| -s }[0, limit].map { |s, t| [s, t] }
    end
  end
end
