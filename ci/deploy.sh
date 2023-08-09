# Deploy the application to a remote server
#
# Usaage: deploy.sh tag user@host
#   The tag is the git tag to deploy
#   The user@host is the user and host to deploy to
#
# Prerequisites:
#   - The user@host must have access to the private container registry (and be logged in)
#   - The images have to be built beforehand with the given tag
#   - RAILS_MASTER_KEY must be set in the environment

DEPLOY_DIR=masdif
ENV_FILE=.env.deploy
MASTER_KEY=$RAILS_MASTER_KEY
USER_HOST=$2
TAG=$1

set -eo pipefail

if [ -z "$TAG" ]; then
    echo "tag is missing"
    echo "Usage: deploy.sh tag user@host"
    exit 1
fi
if [ -z "$USER_HOST" ]; then
    echo "user@host is missing"
    echo "Usage: deploy.sh tag user@host"
    exit 1
fi

if [ -z "$MASTER_KEY" ]; then
    echo "variable RAILS_MASTER_KEY is not set"
    exit 1
fi

# ADMIN_USER, ADMIN_PASSWORD are set via Rails credentials

# Prepare .env file on server
cp .env.example $ENV_FILE
echo "APPLICATION_VERSION=$TAG" >> $ENV_FILE
# we use also the TAG for the GIT_TAG variable, which determines the version that is displayed in the admin interface
echo "GIT_TAG=$TAG" >> $ENV_FILE
echo "ADMIN_INTERFACE_ENABLED=true" >>  $ENV_FILE

# These variables are set from withing the CI/CD pipeline
echo "RAILS_MASTER_KEY=$MASTER_KEY" >> $ENV_FILE

# Create directory $DEPLOY_DIR with subdirectories on remote server
# Copy the following files into $DEPLOY_DIR on remote server :
#   - docker-compose.yml
#   - masdif_override_template.yml
#   - $ENV_FILE
#   - Rasa configuration files and Rasa model
ssh "$USER_HOST" "mkdir -p $DEPLOY_DIR"
ssh "$USER_HOST" "mkdir -p $DEPLOY_DIR/rasa/models"

ssh "$USER_HOST" "mkdir -p $DEPLOY_DIR/rasa/cache"
ssh "$USER_HOST" "mkdir -p $DEPLOY_DIR/config/rasa"

# remove old Rasa models
ssh "$USER_HOST" "rm -f $DEPLOY_DIR/rasa/models/*"

scp config/rasa/endpoints.yml "$USER_HOST":$DEPLOY_DIR/config/rasa
scp config/rasa/credentials.yml "$USER_HOST":$DEPLOY_DIR/config/rasa
scp rasa/config.yml "$USER_HOST":$DEPLOY_DIR/rasa
scp docker-compose.yml "$USER_HOST":$DEPLOY_DIR
scp rasa/masdif_override_template.yml "$USER_HOST":$DEPLOY_DIR/rasa
scp $ENV_FILE "$USER_HOST":$DEPLOY_DIR/.env
# remove the env file immediately from local build machine
rm $ENV_FILE
scp rasa/models/* "$USER_HOST":$DEPLOY_DIR/rasa/models

# Pull all Masdif images from container registry, use the tag from the environment variable APPLICATION_VERSION
# Note: we use docker compose here instead of docker-compose !
ssh "$USER_HOST" "cd $DEPLOY_DIR && cat docker-compose.yml rasa/masdif_override_template.yml | docker compose -f - pull"

# Stop eventually running Masdif containers
ssh "$USER_HOST" "cd $DEPLOY_DIR && cat docker-compose.yml rasa/masdif_override_template.yml | docker compose -f - down"

# Start Masdif containers
ssh "$USER_HOST" "cd $DEPLOY_DIR && cat docker-compose.yml rasa/masdif_override_template.yml | docker compose -f - up -d --no-build"

# run rails migration on server
ssh "$USER_HOST" "cd $DEPLOY_DIR && docker compose exec -it masdif bin/rails db:prepare"
