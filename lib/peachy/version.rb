# frozen_string_literal: true

module Peachy
  module Version
    module_function

    def major
      0
    end

    def minor
      1
    end

    def patch
      0
    end

    def to_a
      [major, minor, patch].compact
    end

    def to_s
      components = [to_a.join('.')]
      components.join
    end
  end
end
