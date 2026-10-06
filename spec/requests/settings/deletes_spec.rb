# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings Deletes' do
  describe 'DELETE /settings/delete' do
    context 'when signed in' do
      before { sign_in(user) }

      let(:user) { Fabricate(:user) }

      it 'gracefully handles invalid nested params' do
        delete settings_delete_path(form_delete_confirmation: 'invalid')

        expect(response)
          .to have_http_status(400)
      end

      it 'rejects a missing username without deleting the account' do
        expect do
          delete settings_delete_path, params: { form_delete_confirmation: { password: user.password } }
        end.to not_change { user.account.reload.requested_deletion_at }

        expect(response).to redirect_to(settings_delete_path)
        expect(flash[:alert]).to eq(I18n.t('deletes.challenge_not_passed'))
      end

      context 'when suspended' do
        let(:user) { Fabricate(:user, account_attributes: { suspended_at: Time.now.utc }) }

        it 'returns http forbidden' do
          delete settings_delete_path

          expect(response)
            .to have_http_status(403)
        end
      end

      context 'when already deleted' do
        let(:user) { Fabricate(:user, account_attributes: { requested_deletion_at: Time.now.utc }) }

        it 'returns http forbidden' do
          delete settings_delete_path

          expect(response)
            .to have_http_status(403)
        end
      end
    end

    context 'when not signed in' do
      it 'redirects to sign in' do
        delete settings_delete_path

        expect(response)
          .to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET /settings/delete' do
    context 'when signed in' do
      before { sign_in(user) }

      context 'when suspended' do
        let(:user) { Fabricate(:user, account_attributes: { suspended_at: Time.now.utc }) }

        it 'returns http forbidden with private cache control headers' do
          get settings_delete_path

          expect(response)
            .to have_http_status(403)
          expect(response.headers['Cache-Control'])
            .to include('private, no-store')
        end
      end

      context 'when already deleted' do
        let(:user) { Fabricate(:user, account_attributes: { requested_deletion_at: Time.now.utc }) }

        it 'returns http forbidden' do
          get settings_delete_path

          expect(response)
            .to have_http_status(403)
        end
      end
    end

    context 'when not signed in' do
      it 'redirects to sign in' do
        get settings_delete_path

        expect(response)
          .to redirect_to(new_user_session_path)
      end
    end
  end
end
