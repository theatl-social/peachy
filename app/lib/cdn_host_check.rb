# frozen_string_literal: true

# Reports CDN_HOST misconfigurations that are otherwise silent.
#
# CDN_HOST is read in two places that cannot see each other: Vite bakes it into
# compiled CSS at build time, and Rails reads it at boot for `asset_host`, which
# drives the CSP allow-list and the `<meta name="cdn-host">` tag. Nothing forces
# the two to agree, and when they disagree the failure is a browser-side blocked
# request rather than anything visible in the server logs.
#
# Everything here is advisory. A warning must never stop the app from booting --
# an instance serving assets from the wrong origin is degraded, not broken, and
# refusing to start would turn a cosmetic problem into an outage.
class CdnHostCheck
  # Written by RecordAssetBase in config/vite/asset-base.ts during a production
  # asset build. Absent for source checkouts that have never compiled assets.
  MANIFEST_PATH = 'packs/.vite/asset-base.json'

  def initialize(env: ENV, public_path: Rails.public_path, rails_env: Rails.env)
    @env = env
    @public_path = public_path
    @rails_env = rails_env
  end

  def warnings
    return [] if configured_host.blank?

    [development_warning, mismatch_warning, service_worker_notice].compact
  end

  # The host the compiled assets were built against, or nil when unknown.
  def built_host
    return @built_host if defined?(@built_host)

    @built_host = begin
      file = @public_path.join(MANIFEST_PATH)
      JSON.parse(file.read)['cdnHost'].presence if file.exist?
    rescue JSON::ParserError, SystemCallError
      # A truncated or unreadable file tells us nothing; it is not itself a
      # misconfiguration worth reporting, so fall back to "unknown".
      nil
    end
  end

  private

  def configured_host
    @env['CDN_HOST'].to_s.strip
  end

  def development_warning
    return unless @rails_env.development?

    'CDN_HOST is set in development. Rails will emit CDN URLs, but the Vite dev ' \
      'server serves assets from this origin, so the two will disagree. Unset ' \
      'CDN_HOST unless you are deliberately testing CDN behaviour against a ' \
      'production asset build.'
  end

  def mismatch_warning
    return if built_host.blank? || built_host == normalized_configured_host

    "CDN_HOST is #{configured_host}, but the compiled assets were built against " \
      "#{built_host}. Compiled CSS still points at the origin it was built with, " \
      'so styles and fonts will be fetched from there while the CSP allows only ' \
      'the configured host. Rebuild the assets, or set CDN_HOST to match.'
  end

  def service_worker_notice
    "CDN_HOST is set to #{configured_host}. The service worker is a module " \
      'worker, so its chunk imports are fetched with CORS. The CDN must send ' \
      'Access-Control-Allow-Origin for the asset path, or the worker will fail ' \
      'to install and offline support and push notifications will stop working.'
  end

  def normalized_configured_host
    configured_host.sub(%r{/+\z}, '')
  end
end
