require "test_helper"

class ConversationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # create a new conversation
    post conversations_url, params: { }, as: :json
    json_response = JSON.parse(response.body)
    assert_not_nil json_response['conversation_id']
    @conversation = Conversation.find(json_response['conversation_id'])
    @msg_hi = messages(:hi)
    @msg_button = messages(:button)
    @msg_bless = messages(:bye)
    @msg_phone = messages(:phone)
  end

  # Check presence of mandatory fields.
  # Bot response contains array of elements with keys 'recipient_id', 'text', 'buttons', etc.
  # the minimal response is one element with key 'text' and a string value and key 'recipient_id' with a string value
  # the recipient_id is the conversation_id
  def check_bot_response(conversation_id, parsed_response)
    assert parsed_response.size > 0
    parsed_response.each do |element|
      assert element.key?('recipient_id')
      assert element.key?('text')
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

  test 'should get index' do
    get conversations_url, as: :json
    json_response = JSON.parse(response.body)
    assert json_response.size > 0
    assert_response :success
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

  test 'should show conversation' do
    # first, create a new conversation
    post conversations_url, params: { }, as: :json
    json_response = JSON.parse(response.body)
    conversation = Conversation.new(id: json_response['conversation_id'])
    patch conversation_url(conversation), params: { text: @msg_hi.text }, as: :json

    # now see if we can get some messages
    get conversation_url(@conversation), as: :json
    assert_response :success
    messages_response = response.parsed_body
    assert messages_response.key?('conversation_id')
    assert messages_response.key?('messages')
    assert messages_response['messages'].size > 0
  end

  # Send a message to the bot, create a new conversation beforehand
  test 'should update conversation' do
    post conversations_url, params: { }, as: :json
    json_response = JSON.parse(response.body)
    conversation = Conversation.new(id: json_response['conversation_id'])
    patch conversation_url(conversation), params: { text: @msg_hi.text, metadata: @msg_hi.meta_data }, as: :json
    assert_response :success
    json_response = response.parsed_body
    check_bot_response(conversation.id, json_response)
    check_tts_attachment(json_response)
    check_meta_data(json_response, @msg_hi.meta_data.merge({ 'language' => 'is-IS' }))
  end

  test 'should destroy conversation' do
    assert_difference('Conversation.count', -1) do
      delete conversation_url(@conversation), as: :json
    end
    assert_response :success
  end

  # This test assures that we have a complete conversation flow and that the bot doesn't
  # begin a new conversation when the same conversation_id is passed.
  test 'should have a complete conversation flow' do
    post conversations_url, params: { }, as: :json
    conversation_id = response.parsed_body['conversation_id']
    conversation = Conversation.new(id: conversation_id)

    patch conversation_url(conversation), params: { text: "/restart" }, as: :json
    assert_response :success

    patch conversation_url(conversation), params: { text: @msg_hi.text, metadata: @msg_hi.meta_data }, as: :json
    assert_response :success
    check_bot_response(conversation.id, response.parsed_body)
    check_tts_attachment(response.parsed_body)
    check_meta_data(response.parsed_body, @msg_hi.meta_data)

    patch conversation_url(conversation), params: { text: @msg_phone.text, metadata: @msg_phone.meta_data }, as: :json
    assert_response :success
    check_bot_response(conversation.id, response.parsed_body)
    buttons = response.parsed_body[0]['buttons']
    assert_not_nil buttons
    assert buttons.size > 0
    check_meta_data(response.parsed_body, @msg_phone.meta_data)

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
    conversation = Conversation.new(status: 'inactive')
    conversation.id = SecureRandom.uuid
    patch conversation_url(conversation), params: { text: @msg_hi.text }, as: :json
    assert_response :not_found
  end
end
