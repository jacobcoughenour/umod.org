class String
  def humanize
    # Split PascalCase on upper cases after a lowercase character (ex. WelcomeTP)
    self.gsub(/([[:lower:]\\d])([[:upper:]])/, '\1 \2') \
    # Split PascalCase on first capital after two or more capitals (ex. NPCManager)
    .gsub(/([[:upper:]]{2,})([[:upper:]][[:lower:]\\d])/,'\1 \2') \
    # Split before a number with multiple characters in front of it (ex. Test99Tool)
    .gsub(/(\D{2,})(\d+)/, '\1 \2') \
    # Split PascalCase after a number (ex. C4Logger)
    .gsub(/(\d)/, '\1 \2') \
    # Remove any whitespace from start or end of string
    .strip

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
