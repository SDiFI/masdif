require "test_helper"

class InfoControllerTest < ActionDispatch::IntegrationTest
  setup do
    @@original_masdif_config ||= Rails.application.config.masdif.deep_dup

    # create a new conversation
    post conversations_url, params: { }, as: :json
    json_response = JSON.parse(response.body)
    assert_not_nil json_response['conversation_id']
    @conversation = Conversation.find(json_response['conversation_id'])
    get info_url, params: { id: @conversation.id }, as: :json
    assert_response :success
    @msg_response = JSON.parse(response.body)
  end

  teardown do
    Rails.application.config.masdif = @@original_masdif_config.deep_dup
  end

  test 'should get info' do
    assert @msg_response.size > 0
    pp @msg_response
  end

  test 'should get motd' do
    assert @msg_response['motd'] != nil
    assert @msg_response['motd'].size > 0
    # assert that motd is an non-empty array of strings
    assert @msg_response['motd'].is_a?(Array)
    assert @msg_response['motd'][0].is_a?(String)
    assert @msg_response['motd'][0].size > 0
  end

  test 'should get supported languages' do
    assert @msg_response['supported_languages'] != nil
    assert @msg_response['supported_languages'].size > 0
    assert @msg_response['supported_languages'].is_a?(Array)
    assert @msg_response['supported_languages'][0].is_a?(Hash)
    assert @msg_response['supported_languages'][0].size > 0
  end

  test 'unsupported language should return 404' do
    get info_url, params: { id: @conversation.id, language: 'unsupported' }, as: :json
    assert_response :not_found
  end

  test 'should get values for all supported languages' do
    if @msg_response['supported_languages'].size > 1
      @msg_response['supported_languages'].each do |supported|
        get info_url, params: { id: @conversation.id, language: supported['lang'] }, as: :json
        assert_response :success
      end
    end
  end

  # configuration error tests

  test 'should error out if rasa_intent is not configured' do
    Rails.application.config.masdif[:motd][:rasa_intent] = nil
    get info_url, params: { id: @conversation.id }, as: :json
    assert_response :internal_server_error
  end

  test 'should error out if languages config is not configured' do
    Rails.application.config.masdif[:languages] = nil
    get info_url, params: { id: @conversation.id }, as: :json
    assert_response :internal_server_error
  end

  test 'should error out if supported languages config is not configured' do
    Rails.application.config.masdif[:languages][:supported] = nil
    get info_url, params: { id: @conversation.id }, as: :json
    assert_response :internal_server_error
  end

  test 'should error out if default language is not configured' do
    Rails.application.config.masdif[:languages][:default] = nil
    get info_url, params: { id: @conversation.id }, as: :json
    assert_response :internal_server_error
  end
end
