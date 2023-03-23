MASDIF_CONFIG = YAML.load_file(Rails.root.join('config', 'masdif.yml'))

Rails.application.config.masdif = MASDIF_CONFIG