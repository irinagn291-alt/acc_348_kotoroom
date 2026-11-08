# Managed by gambling-factory. English source copy and stale locale folders
# may remain on disk, but only the Task's languages may reach App Store Connect.
require "json"
require "digest"

module GFDeliverLocales
  class << self
    attr_accessor :release_notes_only
  end

  def self.load(path)
    @release_notes_only = false
    @locales = nil
    codes = JSON.parse(File.read(path))
    unless codes.is_a?(Array) && !codes.empty? && codes.all? { |code| code.is_a?(String) && code.match?(/\A[a-z]{2,3}(?:-[A-Za-z0-9]+)*\z/) }
      raise "Invalid Task locales in #{path}; set the Task's primary language before uploading."
    end
    @locales = codes.uniq.freeze
    prepared = File.join(File.dirname(path), "prepared-metadata.json")
    if File.file?(prepared)
      receipt = JSON.parse(File.read(prepared))
      raise "Prepared metadata languages changed; return to preparation." unless receipt["locales"] == @locales
      files = receipt.fetch("files")
      raise "Prepared metadata has no files." if files.empty?
      root = File.realpath(File.dirname(path))
      files.each do |relative, checksum|
        file = File.expand_path(relative, root)
        unless File.file?(file) && File.realpath(file).start_with?(root + "/") && Digest::SHA256.file(file).hexdigest == checksum
          raise "Prepared metadata missing or changed: #{relative}"
        end
      end
    end
  end

  def self.locales
    raise "No Task locales configured; refusing to upload with default languages." unless @locales
    @locales.dup
  end

  def self.restrict_options(options)
    allowed = locales
    options[:languages] = allowed
    keys = Deliver::UploadMetadata::LOCALISED_VERSION_VALUES.keys + Deliver::UploadMetadata::LOCALISED_APP_VALUES.keys
    keys.each do |key|
      value = options[key]
      options[key] = value.select { |code, _| allowed.include?(code.to_s) } if value.is_a?(Hash)
    end
  end

  def self.select_localizations(rows)
    allowed = locales
    rows.select { |row| allowed.include?(row.locale) }
  end

  def self.upload_release_notes(options)
    raise "What's New cannot submit a review or upload screenshots." if options[:submit_for_review] || !options[:skip_screenshots]
    app = Deliver.cache[:app]
    platform = Spaceship::ConnectAPI::Platform.map(options[:platform])
    version = app.get_edit_app_store_version(platform: platform)
    expected = options[:app_version].to_s
    unless version && !expected.empty? && version.version_string == expected
      raise "What's New requires editable App Store version #{expected}."
    end
    # Validate every file before the first write. Do not load descriptions, App
    # Info, review details or screenshots from the full listing for an UPDATE.
    notes = locales.to_h do |locale|
      path = File.join(options[:metadata_path], locale, "release_notes.txt")
      text = File.read(path, encoding: "UTF-8").strip
      raise "What's New is empty for #{locale}." if text.empty?
      [locale, text]
    end
    rows = version.get_app_store_version_localizations
    notes.each do |locale, text|
      row = rows.find { |item| item.locale == locale }
      if row
        row.update(attributes: { whatsNew: text }) unless row.whats_new == text
      else
        version.create_app_store_version_localization(attributes: { locale: locale, whatsNew: text })
      end
      FastlaneCore::UI.message("What's New uploaded for #{locale}")
    end
  end
end

module GFDeliverLocaleFolders
  def language_folders(root, ignore_validation, expand_sub_folders = false)
    allowed = GFDeliverLocales.locales
    super.select { |folder| allowed.include?(folder.language) }
         .sort_by { |folder| allowed.index(folder.language) }
  end
end
Deliver::Loader.singleton_class.prepend(GFDeliverLocaleFolders)

module GFDeliverMetadataLocales
  def load_from_filesystem
    GFDeliverLocales.restrict_options(options)
    super
    GFDeliverLocales.restrict_options(options)
  end

  def detect_languages
    GFDeliverLocales.locales
  end

  def upload
    GFDeliverLocales.restrict_options(options)
    super
  end
end
Deliver::UploadMetadata.prepend(GFDeliverMetadataLocales)

module GFDeliverRunnerLocales
  def upload_metadata
    return GFDeliverLocales.upload_release_notes(options) if GFDeliverLocales.release_notes_only && !options[:skip_metadata]
    result = super
    return result if options[:skip_metadata]

    # Wait for metadata AND screenshots before changing primary. Only edit
    # the pending version/info; published versions are never pruned here.
    allowed = GFDeliverLocales.locales
    app = Deliver.cache[:app]
    platform = Spaceship::ConnectAPI::Platform.map(options[:platform])
    version = app.get_edit_app_store_version(platform: platform)
    info = app.fetch_edit_app_info
    raise "Cannot reconcile Task locales without an editable App Store version and App Info." unless version && info
    version_rows = version.get_app_store_version_localizations
    info_rows = info.get_app_info_localizations
    missing = (allowed - version_rows.map(&:locale)) | (allowed - info_rows.map(&:locale))
    raise "Task locales missing after upload: #{missing.join(', ')}" unless missing.empty?

    primary = allowed.first
    if app.primary_locale != primary
      app.update(attributes: { primaryLocale: primary })
      app.primary_locale = primary
      FastlaneCore::UI.message("Primary language from the Task: #{primary}")
    end
    (version_rows + info_rows).each do |localization|
      next if allowed.include?(localization.locale)
      localization.delete!
      FastlaneCore::UI.message("Removed localization outside the Task: #{localization.locale}")
    end
    result
  end
end
Deliver::Runner.prepend(GFDeliverRunnerLocales)

module GFDeliverScreenshotLocales
  def upload(options, screenshots)
    allowed = GFDeliverLocales.locales
    super(options, screenshots.select { |shot| allowed.include?(shot.language) })
  end

  def upload_screenshots(localizations, screenshots_per_language, timeout_seconds, tries: 5)
    allowed = GFDeliverLocales.locales
    super(GFDeliverLocales.select_localizations(localizations),
          screenshots_per_language.select { |code, _| allowed.include?(code) },
          timeout_seconds, tries: tries)
  end

  def delete_screenshots(localizations, screenshots_per_language, tries: 5)
    super(GFDeliverLocales.select_localizations(localizations), screenshots_per_language, tries: tries)
  end

  def sort_screenshots(localizations)
    super(GFDeliverLocales.select_localizations(localizations))
  end
end
Deliver::UploadScreenshots.prepend(GFDeliverScreenshotLocales)
