FROM circleci/ruby:3.0.0-rc1-buster-node-browsers

USER root

RUN wget -O nightly.tar.bz2 "https://download.mozilla.org/?product=firefox-nightly-latest-ssl&os=linux64&lang=en-US" \
    && tar xf nightly.tar.bz2 \
    && ln -s $(pwd)/firefox/firefox /usr/bin/firefox

USER circleci
