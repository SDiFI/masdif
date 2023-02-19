#!/bin/bash
set -eo pipefail

# This script is used to test the chat server. It uses curl to send messages to the server and gets the response
# blockingly.

function create_conversation() {
  # POST /conversations - retrieve a new conversation id.
  conversationId=$(curl -s -X POST "${1}"/conversations | jq -r '.conversation_id')
}

function send_msg() {
    # PUT /conversations/{conversationId}   - send new message to the server.
    # The endpoint expects the following JSON body:
    # {
    #   "text": "Hello World!"
    #   "metadata": {
    #     "voice_id": "string",
    #     "language": "string",
    #     "tts": "true/false"
    # }
    response=$(curl -s -X PUT -H "Content-Type: application/json" -d "{\"text\":\"$1\", \"metadata\":{\"voice_id\":\"$2\"}}" "${HOST}"/conversations/"$conversationId")
    echo "Response: $response"
    # we retrieve the tts audio file from the response. The response format is:
    # [{
    # 	"text": "blubber",
    # 	"data": {
    # 		"elements": null,
    # 		"quick_replies": null,
    # 		"buttons": null,
    # 		"attachment": [{
    # 			"type": "audio",
    # 			"payload ": {
    # 				"src ": "https://example.com/audio.mp3"
    # 			}
    # 		}]
    # 	}
    # }]
    # Use jq to retrieve the src field from the attachment object.
    audioUrl=$(echo "$response" | jq -r '.[0].data.attachment[0].payload.src')

    # Download audio file from provided src URL
    curl -s -X GET "$audioUrl" > audio.mp3
}


# HOST variable == Masdif instance
# Default for local development
# HOST=http://localhost:3000
# Default for docker-compose
HOST=http://localhost:8080

# We first retrieve a new conversation id.
create_conversation "$HOST"
echo "Conversation id: $conversationId"

# Send messages and retrieve TTS audio answers
send_msg "Halló" "Karl"
send_msg "hver er bæjarstjóri ?" "Dora"

# Retrieve the conversation history for conversation id
conv_history=$(curl -s -X GET ${HOST}/conversations/"$conversationId")

# and pretty print returned JSON list of conversation messages
echo $conv_history | jq .






