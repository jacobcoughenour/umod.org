#!/bin/bash

sudo apt-get update -y && sudo apt-get upgrade -y
sudo apt-add-repository ppa:brightbox/ruby-ng
sudo apt-get update
sudo apt-get install ruby2.3 ruby2.3-dev build-essential
sudo gem update
sudo gem install -n /usr/local/bin jekyll bundler
sudo bundle update
sudo bundle install --path vendor/bundle

LINK="http://localhost:4000"
if [[ $OSTYPE == "cygwin" ]] || [[ $OSTYPE == "msys" ]]; then
    # http://curl.haxx.se/ca/cacert.pem
    export SSL_CERT_FILE="$CD/vendor/cacert.pem"
    start $LINK
elif [[ $OSTYPE == "darwin"* ]]; then
    open $LINK
elif [[ "$OSTYPE" == "linux-gnu" ]] || [[ $OSTYPE == "freebsd"* ]]; then
    xdg-open $LINK
fi

sudo bundle exec jekyll serve --watch --baseurl=
