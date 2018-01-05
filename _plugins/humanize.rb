class String
  def humanize
    # TODO: Improve this to not require .strip
    self.gsub(/((?<=[a-z])[A-Z]|[A-Z](?=[a-z]))/, ' \0').strip
    # TODO: Add support for other string formats and small words (ie. and, to, or, of)
  end
end

module Jekyll
  module HumanizeFilter
    def humanize(input)
      input.humanize
    end
  end
end

Liquid::Template.register_filter(Jekyll::HumanizeFilter)
