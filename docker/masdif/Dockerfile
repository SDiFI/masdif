FROM ruby:3.2.1-slim-buster

RUN apt-get update -qq && apt-get install -y build-essential libpq-dev ssh sox curl software-properties-common
RUN apt-get install -y git zlib1g-dev liblzma-dev patch pkg-config libxml2-dev libxslt-dev ffmpeg vim
RUN mkdir -p ~/.ssh && ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts

# Set an environment variable where the Rails app is installed to inside of Docker image
ENV RAILS_ROOT /var/www/masdif
RUN mkdir -p $RAILS_ROOT/app/assets/audios
RUN mkdir -p $RAILS_ROOT/tmp/pids/

# Set working directory
WORKDIR $RAILS_ROOT

# Setting env up
ENV RAILS_ENV='production'
ENV RACK_ENV='production'

# Adding gems
COPY Gemfile Gemfile
COPY Gemfile.lock Gemfile.lock
RUN gem install bundler
RUN bundle config set --local path 'vendor'
RUN bundle config set --local without 'development test'
RUN bundle install --jobs 20 --retry 5

# Adding project files
COPY . $RAILS_ROOT

EXPOSE 8080

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]