# frozen_string_literal: true

require 'minitest/autorun'

class VersionControllerTest < ActionDispatch::IntegrationTest

  test 'should get version' do
    get version_url, as: :text
    version_response = response.body
    assert version_response.size > 0
    assert_response :success
  end

end
