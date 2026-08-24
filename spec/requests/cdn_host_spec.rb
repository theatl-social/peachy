# frozen_string_literal: true

require 'rails_helper'

# `CDN_HOST` is applied in two independent places: Vite bakes it into asset URLs
# at build time, and Rails reads it at boot into `config.asset_host`. These specs
# cover the Rails half -- whether the front-end is told a CDN exists, and whether
# the policy that gates asset loading is derived from the asset host at all.
#
# The failure they guard against is a build that sets CDN_HOST at build time but
# not at runtime: assets point at the CDN, Rails boots without an asset host, and
# the browser blocks them. See the `test-cdn-runtime-env` job in
# .github/workflows/test-cdn-assets.yml for the container-level half of this.
RSpec.describe 'CDN host' do
  around do |example|
    original_asset_host = Rails.configuration.action_controller.asset_host
    example.run
    Rails.configuration.action_controller.asset_host = original_asset_host
  end

  let(:cdn_host) { 'https://cdn.example.com' }

  describe 'advertising the CDN to the front-end' do
    # `cdn_host` is a view helper reading `Rails.configuration` per request, so
    # unlike the policy below it does reflect a value changed at runtime.
    context 'when an asset host is configured' do
      before { Rails.configuration.action_controller.asset_host = cdn_host }

      it 'renders the meta tag the front-end reads for emoji, sounds and OCR data' do
        get '/'

        expect(response).to have_http_status(:success)
        expect(cdn_host_meta_content).to eq cdn_host
      end

      it 'preconnects to the CDN' do
        get '/'

        expect(dns_prefetch_hrefs).to include cdn_host
      end
    end

    context 'when no asset host is configured' do
      before { Rails.configuration.action_controller.asset_host = nil }

      it 'renders no CDN meta tag' do
        get '/'

        # Assert the page rendered first: without this the negative expectation
        # would pass just as happily on a redirect or an error page, hiding a
        # regression rather than catching one.
        expect(response).to have_http_status(:success)
        expect(cdn_host_meta_content).to be_nil
      end
    end
  end

  describe 'the content security policy' do
    # The policy cannot be parameterised per example. config/initializers/
    # content_security_policy.rb evaluates `ContentSecurityPolicy#assets_host`
    # into a local at boot and the policy block closes over it, so Rails builds
    # one static policy per process. Changing `asset_host` afterwards has no
    # effect -- which also means a CDN_HOST that only exists at build time can
    # never reach the policy, no matter what the assets were built against.
    #
    # What is worth asserting, then, is the wiring: that the asset origin in the
    # policy is derived from the asset host rather than hardcoded. Whatever
    # `assets_host` resolves to at boot is what these directives must name, so
    # when CDN_HOST is set at boot the CDN lands here. That `assets_host`
    # returns the CDN when an asset host is configured is covered by
    # spec/lib/content_security_policy_spec.rb.
    let(:boot_assets_host) { ContentSecurityPolicy.new.assets_host }

    before do
      Rails.configuration.action_controller.asset_host = nil
      get '/'
    end

    it 'derives the script origin from the asset host' do
      expect(csp_directive('script-src')).to include boot_assets_host
    end

    it 'derives the style origin from the asset host' do
      expect(csp_directive('style-src')).to include boot_assets_host
    end

    it 'derives the font origin from the asset host' do
      expect(csp_directive('font-src')).to include boot_assets_host
    end

    it 'derives the image origin from the asset host' do
      expect(csp_directive('img-src')).to include boot_assets_host
    end
  end

  private

  def parsed_page
    # `parsed_body` yields a Nokogiri document for HTML responses.
    response.parsed_body
  end

  def cdn_host_meta_content
    parsed_page.at_css('meta[name="cdn-host"]')&.attribute('content')&.value
  end

  def dns_prefetch_hrefs
    parsed_page.css('link[rel="dns-prefetch"]').map { |link| link.attribute('href').value }
  end

  def csp_directive(name)
    response
      .headers['Content-Security-Policy']
      .split(';')
      .map(&:strip)
      .find { |directive| directive.start_with?("#{name} ") }
      .to_s
  end
end
