require "test_helper"

class ChatControllerTest < ActionDispatch::IntegrationTest
  setup do
    @config =  Rails.application.config.masdif['chat_widget']
  end

  test 'should get web-chat page and load successfully' do
    get @config['path']
    assert_response :success
  end
end