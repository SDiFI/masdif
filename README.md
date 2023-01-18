# Masdif - The Sdifi chatbot Manager 

This project is a front-facing manager service for Icelandic chatbots. Masdif is a Rails application and centralizes
access to Icelandic conversational services like ASR, TTS and the dialog framework. It aims to be independent from the
used dialog system, but is currently based on the Rasa framework.
We provide configurations for using Rasa in Icelandic, so that Rasa can be used also standalone even without Masdif.

The manager provides a central place for saving chat, ASR and TTS logs into a database. Furthermore, it connects to
RabbitMQ and Redis for external communication or for functional extension points. 

# General architecture

## Frontend API

Masdif provides a REST API for the frontend. We provide a web widget that can be easily integrated into a web page.
This widget is based on [rasa-webchat](https://github.com/botfront/rasa-webchat), adapted to Restful API calls instead
of using socket.io.

The following API endpoints are provided:

- `GET  /` - shows the OpenAPI documentation
- `GET  /webchat` - serves the webchat widget
- `GET  /status` - Returns the status of the API
- `GET  /version` - Returns the version of the Manager
- `GET  /conversations` - Returns a list of all conversations
- `GET  /conversations/:id` - Returns a single conversation
- `GET  /conversations/:id/logs` - Returns all logs for a conversation
- `POST /conversations/` - Creates a new conversation, returns JSON with the conversation id
- `POST /conversations/:id` - Appends message to conversation with given id
- `POST /conversations/:id/audio` - Appends audio recording to conversation with given id

The client sends messages via POST requests to Masdif. The POST request blocks on completion of all involved services.

##  Conversational services

### ASR

For ASR, POST requests can be sent to the audio endpoint of the Masdif API. Masdif then forwards the given audio to
the ASR service and uses the highest ranked result as new message to the dialog backend. The POST requests returns the
ASR result together with the answer from the dialog system.
Alternatively, you can use the gRPC endpoint either by sending audio synchronously to it or via a streaming request.
The latter is preferred for performance reasons and the webchat widget does this by default. 

ASR gRPC is implemented via 2 hops: a gRPC proxy and the real gRPC ASR service. The proxy mediates the users audio to
the real gRPC service and publishes it also via RabbitMQ to make it possible for more services to work on it, e.g.
for sentiment analysis or to control a virtual avatar.
If audio streaming is used, the ASR service streams back its results as soon as text is recognized. Previously returned
text can be corrected again depending on the users utterances, which gives the widget a sort of "live" feeling.
This is not possible if synchronous calls are used. Furthermore, streaming mode enables endpoint detection, which makes
it possible to detect when a user has stopped speaking, i.e. in the presence of silence.

Our web chatbot widget provides a button to activate audio recording. As soon as the ASR service detects end of audio,
it sends a stop response to the widget which disables the audio recording button and sends all so far recognized text
to Masdif via a normal POST request.

### TTS

After Masdif receives the chatbot response and if TTS is configured for the message (which is the default), Masdif 
calls the TTS service and publishes the returned voice audio via RabbitMQ. To the client, the text response from the
dialog framework is sent as well as a link to the generated audio file.

### Dialog framework

The dialog framework adaption is split into 2 parts: the communication and the data abstraction.

#### Rasa Rest API

For communication to Rasa, the proxy service uses the Rasa Rest API https://rasa.com/docs/rasa/pages/http-api/.
The proxy service is configured with the URL of the Rasa server. A typical request to the Rasa server looks like this:

```json
{
  "sender": "test_user",
  "message": "Hi there!"
}
```

The Rasa service returns its response by calling a webhook. The webhook is configured in Masdif as well as inside the
Rasa server. The webhook is called with the following example JSON:

```json
{
  "sender": "test_user",
  "message": "Hi there!",
  "response": [
    {"text": "Hey Rasa!"},
    {"image": "http://example.com/image.jpg"}
  ]
}
```

## Chat session management

Rails provides already enough functionality for session management. We use the session cookie to store the session ID.
The session ID is used to identify the user in the database. The session ID is also used to identify the user in the Rasa
server. The Rasa server is configured to use the session ID as the sender ID. This way, the Rasa server can identify the
user and can store the user's conversation history in the database.

TODO:
- [ ] Add a session timeout
- [ ] Add a session cleanup
- [ ] Add a session cleanup for the Rasa server

# Installation
TODO
## Prerequisites
TODO
## Docker
TODO
# Development

## `config/master.key` File
The file `config/master.key` is the de-/encryption key file used for access tokens in `config/credentials.yml.enc`.
This file is not under version control, but is packaged together with the container. Therefore, the container should not
be publicly accessible !
