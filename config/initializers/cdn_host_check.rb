# frozen_string_literal: true

# Surface CDN_HOST misconfigurations at boot. See app/lib/cdn_host_check.rb for
# why these cases are invisible otherwise.
#
# Required rather than autoloaded, matching content_security_policy.rb: the
# check is skipped under test, so the constant reference here is never exercised
# by the suite, and an autoloading problem would surface only in a real
# deployment. `require_relative` removes the question entirely.
require_relative '../../app/lib/cdn_host_check'

Rails.application.config.after_initialize do
  # Skipped under test, where the warnings would be noise on every example run.
  next if Rails.env.test?

  CdnHostCheck.new.warnings.each { |warning| Rails.logger.warn("[CDN_HOST] #{warning}") }
end
