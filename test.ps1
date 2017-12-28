# Fix not starting from root directory

gem install bundle jekyll
gem update bundler
bundle update
bundle install --path vendor/bundle

# https://curl.haxx.se/ca/cacert.pem
$env:SSL_CERT_FILE = "$PSScriptRoot/vendor/cacert.pem"
bundle exec jekyll serve --watch --baseurl=
