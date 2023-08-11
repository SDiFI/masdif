# frozen_string_literal: true

require 'minitest/autorun'

class VersionControllerTest < ActionDispatch::IntegrationTest
  include VersionHelper

  test 'should get version' do
    get version_url, as: :text
    version_response = response.body
    assert version_response.size > 0
    assert_response :success
  end

  test 'should convert version to integer and vice versa' do
    assert_equal 304, version_as_int('v0.3.4')
    assert_equal 10415, version_as_int('v1.4.15')
    assert_equal 'v0.3.4', int_as_version(304)
    assert_equal 'v1.4.15', int_as_version(10415)
  end

end
