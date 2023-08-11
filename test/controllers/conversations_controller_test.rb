require "test_helper"

class ConversationsControllerTest < ActionDispatch::IntegrationTest
  include VersionHelper

  setup do
    # create a new conversation
    post conversations_url, params: { }, as: :json
    json_response = JSON.parse(response.body)
    assert_not_nil json_response['conversation_id']
    @conversation = Conversation.find(json_response['conversation_id'])
    @msg_hi = messages(:hi)
    @msg_baejastjori = messages(:baejastjori)
    @msg_bless = messages(:bye)
    @msg_phone = messages(:phone)
    @msg_library = messages(:library)
    @msg_feedback = messages(:feedback)
  end

  # Check presence of mandatory fields for a general response.
  # Bot response contains array of elements with keys 'recipient_id', 'text', 'buttons', etc.
  # The minimal response is at least one element with key 'text', 'data', 'buttons' or 'custom'.
  # These keys needs always to be provided: 'recipient_id', 'message_id', 'metadata'.
  def check_bot_response(conversation_id, parsed_response)
    assert parsed_response.size > 0
    parsed_response.each do |element|
      assert element.key?('recipient_id')
      assert element.key?('message_id')
      assert element.key?('metadata')
      assert(element.key?('text') || element.key?('data') || element.key?('buttons') || element.key?('custom'))
      assert_equal conversation_id, element['recipient_id']
    end
  end

  # Check presence of mandatory fields for a feedback response.
  # Bot response contains array of elements with keys 'recipient_id', 'message_id', text', 'buttons', etc.
  # The response can contain the same elements as a normal bot response, but can omit elements in case the feedback
  # is not sent to the dialog system.
  # These keys needs always to be provided: 'recipient_id', 'message_id', 'metadata'.
  def check_feedback_response(conversation_id, parsed_response)
    assert parsed_response.size > 0
    parsed_response.each do |element|
      assert element.key?('recipient_id')
      assert element.key?('message_id')
      assert element.key?('metadata')
      assert_equal conversation_id, element['recipient_id']
    end
  end

  # Check if the bot response contains a tts attachment
  def check_tts_attachment(json_response)
    json_response.each do |element|
      if element.key?('data')
        assert element['data'].key?('attachment')
        assert element['data']['attachment'].size > 0
        assert element['data']['attachment'][0].key?('type')
        assert element['data']['attachment'][0].key?('payload')
        assert element['data']['attachment'][0]['payload'].key?('src')
        assert element['data']['attachment'][0]['payload']['src'].size > 0
      end
    end
  end

  # Check if the bot response contains metadata
  def check_meta_data(json_response, kwargs)
    json_response.each do |element|
      assert element.key?('metadata')
      # all metadata keys given in kwargs must be present
      kwargs.each do |key, value|
        assert element['metadata'].key?(key.to_s)
        assert_equal value, element['metadata'][key.to_s]
      end
    end
  end

  # Tests returning of a new conversation id
  test 'should create conversation' do
    assert_difference('Conversation.count') do
      post conversations_url, params: { }, as: :json
      json_response = JSON.parse(response.body)
      assert_not_nil json_response['conversation_id']
    end
    assert_response :ok
  end

  # Send a message to the bot, create a new conversation beforehand
  test 'should update conversation' do
    post conversations_url, params: { }, as: :json
    json_response = JSON.parse(response.body)
    application_version = 'v10.12.1'
    conversation = Conversation.new(id: json_response['conversation_id'], masdif_version: application_version)
    assert conversation.masdif_version == application_version
    patch conversation_url(conversation), params: { text: @msg_hi.text, metadata: @msg_hi.meta_data }, as: :json
    assert_response :success
    json_response = response.parsed_body
    check_bot_response(conversation.id, json_response)
    check_tts_attachment(json_response)
    check_meta_data(json_response, @msg_hi.meta_data.merge({ 'language' => 'is-IS' }))
  end

  # This test assures that we have a complete conversation flow and that the bot doesn't
  # begin a new conversation when the same conversation_id is passed.
  test 'should have a complete conversation flow' do
    post conversations_url, params: { }, as: :json
    conversation_id = response.parsed_body['conversation_id']
    conversation = Conversation.new(id: conversation_id, masdif_version: app_version)

    patch conversation_url(conversation), params: { text: "/restart" }, as: :json
    assert_response :success

    patch conversation_url(conversation), params: { text: @msg_hi.text, metadata: @msg_hi.meta_data }, as: :json
    assert_response :success
    check_bot_response(conversation.id, response.parsed_body)
    check_tts_attachment(response.parsed_body)
    check_meta_data(response.parsed_body, @msg_hi.meta_data)

    patch conversation_url(conversation), params: { text: @msg_library.text, metadata: @msg_library.meta_data }, as: :json
    assert_response :success
    check_bot_response(conversation.id, response.parsed_body)
    buttons = response.parsed_body[0]['buttons']
    assert_not_nil buttons
    assert buttons.size > 0
    check_meta_data(response.parsed_body, @msg_library.meta_data)

    # send payload of the first button
    patch conversation_url(conversation), params: { text: buttons[0]['payload'], metadata: { tts: false } }, as: :json
    assert_response :success
    check_bot_response(conversation.id, response.parsed_body)
    check_tts_attachment(response.parsed_body)
    check_meta_data(response.parsed_body, { tts: false })

    patch conversation_url(conversation), params: { text: @msg_phone.text, metadata: {} }, as: :json
    assert_response :success
    check_bot_response(conversation.id, response.parsed_body)
    check_tts_attachment(response.parsed_body)

    patch conversation_url(conversation), params: { text: @msg_bless.text, metadata: {} }, as: :json
    assert_response :success
    check_bot_response(conversation.id, response.parsed_body)
    check_tts_attachment(response.parsed_body)
  end

  test 'should return 404 in case an invalid conversation id is given' do
    # implement
    conversation = Conversation.new(status: 'inactive', masdif_version: app_version)
    conversation.id = SecureRandom.uuid
    patch conversation_url(conversation), params: { text: @msg_hi.text }, as: :json
    assert_response :not_found
  end

  # Send feedback for a message to the bot
  test 'should post feedback' do
    post conversations_url, params: { }, as: :json
    json_response = JSON.parse(response.body)
    conversation = Conversation.new(id: json_response['conversation_id'], masdif_version: app_version)
    patch conversation_url(conversation), params: { text: @msg_baejastjori.text,
                                                    metadata: @msg_baejastjori.meta_data }, as: :json
    assert_response :success
    json_response = response.parsed_body
    message_id = json_response[0]['message_id']
    assert_not_nil message_id
    # send 1. feedback
    patch conversation_url(conversation), params: { text: @msg_feedback.text,
                                                    message_id: message_id,
                                                    metadata: @msg_feedback.meta_data }, as: :json
    assert_response :success
    check_feedback_response(conversation.id, response.parsed_body)

    # send 2. feedback with the same message_id, but different feedback value
    patch conversation_url(conversation), params: { text: '/feedback{"value":"supa-dupa"}',
                                                    message_id: message_id,
                                                    metadata: @msg_feedback.meta_data }, as: :json
    assert_response :success
    check_feedback_response(conversation.id, response.parsed_body)

    feedback_in_db = conversation.messages.find_by(id: message_id).feedback
    assert feedback_in_db == "supa-dupa"
  end

  # Send ill-formed feedback for a message to the bot
  test 'should not accept ill-formed feedback' do
    # first create a conversation and send a normal message
    post conversations_url, params: { }, as: :json
    json_response = JSON.parse(response.body)
    conversation = Conversation.new(id: json_response['conversation_id'], masdif_version: app_version)
    patch conversation_url(conversation), params: { text: @msg_baejastjori.text,
                                                    metadata: @msg_baejastjori.meta_data }, as: :json
    assert_response :success
    json_response = response.parsed_body
    valid_message_id = json_response[0]['message_id']
    invalid_message_id = "some-ill-formed-message-id"

    # use invalid message_id
    patch conversation_url(conversation), params: { text: @msg_feedback.text,
                                                    message_id: invalid_message_id,
                                                    metadata: @msg_feedback.meta_data }, as: :json
    assert_response :not_found

    # no message_id
    patch conversation_url(conversation), params: { text: @msg_feedback.text,
                                                    metadata: @msg_feedback.meta_data }, as: :json
    assert_response :bad_request

    # malformed feedback semantics
    patch conversation_url(conversation), params: { text: '/feedback{"val":"some-value"}',
                                                    message_id: valid_message_id,
                                                    metadata: @msg_feedback.meta_data }, as: :json
    assert_response :bad_request

    # invalid JSON
    patch conversation_url(conversation), params: { text: '/feedback["some"@"gibberish',
                                                    message_id: valid_message_id,
                                                    metadata: @msg_feedback.meta_data }, as: :json
    assert_response :bad_request
  end
end
