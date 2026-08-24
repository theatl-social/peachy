# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CdnHostCheck do
  subject(:check) { described_class.new(env: env, public_path: public_path, rails_env: rails_env) }

  let(:env) { {} }
  let(:rails_env) { ActiveSupport::StringInquirer.new('production') }
  let(:public_path) { Pathname.new(Dir.mktmpdir) }

  after { FileUtils.remove_entry(public_path) }

  def record_built_host(value)
    path = public_path.join(described_class::MANIFEST_PATH)
    FileUtils.mkdir_p(path.dirname)
    path.write({ base: "#{value}/packs/", cdnHost: value }.to_json)
  end

  def write_raw_manifest(contents)
    path = public_path.join(described_class::MANIFEST_PATH)
    FileUtils.mkdir_p(path.dirname)
    path.write(contents)
  end

  describe '#warnings' do
    context 'when CDN_HOST is not set' do
      it 'reports nothing' do
        expect(check.warnings).to be_empty
      end
    end

    context 'when CDN_HOST is blank' do
      let(:env) { { 'CDN_HOST' => '   ' } }

      it 'reports nothing' do
        expect(check.warnings).to be_empty
      end
    end

    context 'when CDN_HOST is set' do
      let(:env) { { 'CDN_HOST' => 'https://cdn.example.com' } }

      it 'notes the service worker CORS requirement' do
        expect(check.warnings).to include(a_string_matching(/Access-Control-Allow-Origin/))
      end

      context 'with no recorded build' do
        it 'does not claim a mismatch it cannot know about' do
          expect(check.warnings).to_not include(a_string_matching(/built against/))
        end
      end

      context 'when the assets were built against the same host' do
        before { record_built_host('https://cdn.example.com') }

        it 'reports no mismatch' do
          expect(check.warnings).to_not include(a_string_matching(/built against/))
        end
      end

      context 'when the assets were built against a different host' do
        before { record_built_host('https://old-cdn.example.com') }

        it 'reports the mismatch with both hosts' do
          expect(check.warnings)
            .to include(a_string_matching(%r{https://cdn\.example\.com.*https://old-cdn\.example\.com}m))
        end
      end

      context 'when the assets were built with no CDN' do
        before { record_built_host(nil) }

        it 'treats an unrecorded host as unknown rather than a mismatch' do
          expect(check.warnings).to_not include(a_string_matching(/built against/))
        end
      end

      context 'when the recorded file is corrupt' do
        before { write_raw_manifest('{ not json') }

        it 'ignores it rather than raising' do
          expect { check.warnings }.to_not raise_error
          expect(check.warnings).to_not include(a_string_matching(/built against/))
        end
      end

      context 'when an older build recorded an unnormalised host' do
        # Builds before the Vite side normalised this wrote the raw CDN_HOST,
        # trailing slash and all. Comparing that against a normalised runtime
        # value would report a host as mismatching itself on every boot.
        before { record_built_host('https://cdn.example.com/') }

        it 'does not report a host as mismatching itself' do
          expect(check.warnings).to_not include(a_string_matching(/built against/))
        end
      end

      context 'when only a trailing slash differs' do
        let(:env) { { 'CDN_HOST' => 'https://cdn.example.com/' } }

        before { record_built_host('https://cdn.example.com') }

        it 'does not report a spurious mismatch' do
          expect(check.warnings).to_not include(a_string_matching(/built against/))
        end
      end

      context 'when running in development' do
        let(:rails_env) { ActiveSupport::StringInquirer.new('development') }

        it 'warns that Vite serves assets from this origin instead' do
          expect(check.warnings).to include(a_string_matching(/Vite dev/))
        end
      end

      context 'when running in production' do
        it 'does not emit the development warning' do
          expect(check.warnings).to_not include(a_string_matching(/Vite dev/))
        end
      end
    end
  end
end
