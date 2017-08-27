#!/bin/bash

# Fix not starting from root directory

sudo gem install -n /usr/local/bin bundle
gem update bundler
bundle update
bundle install --path vendor/bundle
sudo bundle exec jekyll serve --watch --baseurl=
