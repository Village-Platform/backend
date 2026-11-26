require "active_storage/service"

module ActiveStorage
  # Active Storage service that keeps file bodies in PostgreSQL (table "stored_files").
  #
  # Made for hosts without a persistent disk. It suits small private files
  # (payment screenshots up to a few MB). For many or large files, switch to S3 / R2.
  #
  #   # config/storage.yml
  #   database:
  #     service: Database
  #
  # URLs are signed and expire like the Disk service ones; they are served by StoredFilesController.
  class Service::DatabaseService < Service
    def upload(key, io, checksum: nil, **)
      instrument :upload, key:, checksum: do
        data = io.read
        ensure_integrity_of(data, checksum) if checksum
        StoredFile.upsert({ key:, data:, created_at: Time.current }, unique_by: :key)
      end
    end

    def download(key, &block)
      if block_given?
        instrument :streaming_download, key: do
          yield fetch_data(key)
        end
      else
        instrument :download, key: do
          fetch_data(key)
        end
      end
    end

    def download_chunk(key, range)
      instrument :download_chunk, key:, range: do
        # Files here are small, so reading the whole body and slicing it is fine.
        fetch_data(key).byteslice(range) || "".b
      end
    end

    def delete(key)
      instrument :delete, key: do
        StoredFile.where(key:).delete_all
      end
    end

    def delete_prefixed(prefix)
      instrument :delete_prefixed, prefix: do
        StoredFile.where("key LIKE ?", "#{StoredFile.sanitize_sql_like(prefix)}%").delete_all
      end
    end

    def exist?(key)
      instrument :exist, key: do |payload|
        payload[:exist] = StoredFile.exists?(key:)
      end
    end

    def compose(source_keys, destination_key, **)
      data = source_keys.map { |source_key| fetch_data(source_key) }.join
      StoredFile.upsert({ key: destination_key, data:, created_at: Time.current }, unique_by: :key)
    end

    def url_for_direct_upload(*)
      raise NotImplementedError, "Direct uploads are not supported by the database service"
    end

    private

    def private_url(key, expires_in:, filename:, content_type:, disposition:, **)
      generate_url(key, expires_in:, filename:, content_type:, disposition:)
    end

    def public_url(key, filename:, content_type: nil, disposition: :attachment, **)
      generate_url(key, expires_in: nil, filename:, content_type:, disposition:)
    end

    def generate_url(key, expires_in:, filename:, content_type:, disposition:)
      token = ActiveStorage.verifier.generate(
        {
          key:,
          disposition: content_disposition_with(type: disposition, filename:),
          content_type:,
          service_name: name
        },
        expires_in:,
        purpose: :blob_key
      )

      helpers = Rails.application.routes.url_helpers
      url_options = ActiveStorage::Current.url_options
      if url_options.present?
        helpers.stored_file_url(token, filename:, **url_options)
      else
        helpers.stored_file_path(token, filename:)
      end
    end

    def fetch_data(key)
      data = StoredFile.where(key:).pick(:data) # cast by the binary attribute type
      raise ActiveStorage::FileNotFoundError if data.nil?

      data.b
    end

    def ensure_integrity_of(data, checksum)
      unless OpenSSL::Digest::MD5.base64digest(data) == checksum
        raise ActiveStorage::IntegrityError
      end
    end
  end
end
