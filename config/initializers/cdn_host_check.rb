# frozen_string_literal: true

# Surface CDN_HOST misconfigurations at boot. See app/lib/cdn_host_check.rb for
# why these cases are invisible otherwise. Skipped under test, where the warnings
# would be noise on every example run.
Rails.application.config.after_initialize do
  next if Rails.env.test?

  CdnHostCheck.new.warnings.each { |warning| Rails.logger.warn("[CDN_HOST] #{warning}") }
end
