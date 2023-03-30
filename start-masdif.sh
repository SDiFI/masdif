#!/bin/bash

# Start Masdif together with Rasa bot, prepare any required files, folders and dependencies.

# Note: This file is a demonstration of how to start one of the SDiFI Rasa demo bots. You might want to adapt it to
# your development/deployment environment and Rasa bot.

RASA_REPO_NAME=sdifi_rasa_akranes
RASA_REPO_DIR=rasa
PYTHON_VER=3.9

# we need a certain version of Python, otherwise the Rasa installation will fail
which pyenv || curl https://pyenv.run | bash
eval "$(pyenv init -)"
python3 --version | grep $PYTHON_VER
if [ $? == 1 ]; then
  echo "Python $PYTHON_VER not installed, install it as prerequisite for Rasa ..."
  pyenv install $PYTHON_VER
  pyenv local $PYTHON_VER
fi

# Clone repo, if not already cloned
if [ ! -d "$RASA_REPO_NAME" ]; then
    git clone https://github.com/SDiFI/$RASA_REPO_NAME.git RASA_REPO_DIR
    pushd $RASA_REPO_DIR || exit 1

    # install Rasa
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt

    # train a model
    rasa train

    # prepare the Rasa Dockers
    cp .env.template .env
    docker-compose build
    popd || exit 1
fi

# prepare Masdif
#C reate new credentials if not already present
if [ ! -f "config/master.key" ]; then
    export EDITOR=cat
    rails credentials:edit
    RAILS_MASTER_KEY=$(cat config/master.key)
    echo "RAILS_MASTER_KEY=$RAILS_MASTER_KEY" >> .env
fi

# build Masdif stack
docker-compose -f docker-compose.yml -f $RASA_REPO_DIR/masdif_override_template.yml build
# combine the local docker-compose.yml with the Masdif override template of the Rasa bot and start the whole stack
cat docker-compose.yml $RASA_REPO_DIR/masdif_override_template.yml | docker-compose -f - up
