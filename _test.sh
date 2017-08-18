#!/bin/bash

# Fix not starting from root directory

sudo gem install -n /usr/local/bin bundle
gem update bundler

bundle update
bundle install --path vendor/bundle

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
