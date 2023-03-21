# frozen_string_literal: true

require 'minitest/autorun'

class HealthControllerTest < ActionDispatch::IntegrationTest

  test 'should get health status' do
    get health_url, as: :json
    json_response = JSON.parse(response.body)
    assert json_response.size > 0
    assert_response :success
  end

  test 'health message should contain all required services' do
    get health_url, as: :json
    json_response = JSON.parse(response.body)
    assert_response :success
    all_services = %w[database dialog_system masdif tts sidekiq]
    json_response.each do |element|
      all_services.delete(element[0])
    end
    assert all_services.empty?
  end
end
