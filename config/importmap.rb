# Pin npm packages by running ./bin/importmap

pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true
pin "sdifi_webchat", to: "https://cdn.jsdelivr.net/npm/@sdifi/webchat@0.2.1/dist/webchat.umd.production.min.js"
pin_all_from "app/javascript/controllers", under: "controllers"
