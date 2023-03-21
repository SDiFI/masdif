# frozen_string_literal: true

require "test_helper"

class OptionsControllerTest < ActionDispatch::IntegrationTest
  test 'should return correct options when origin is different from base domain' do
    # check if we can get the options and set origin header to sdifi-project.com
    options '/', headers: { 'Origin' => 'https://sdifi-project.com' }
    assert_response :ok
    assert_equal '*', response.headers['Access-Control-Allow-Origin']
    assert_equal 'Authorization', response.headers['Access-Control-Expose-Headers']
    assert_equal '1728000', response.headers['Access-Control-Max-Age']
    assert_equal 'GET, PATCH, POST, PUT, DELETE, OPTIONS', response.headers['Access-Control-Allow-Methods']
  end
end
