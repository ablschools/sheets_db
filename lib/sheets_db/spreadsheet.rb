module SheetsDB
  class Spreadsheet < Resource
    class WorksheetAssociationAlreadyRegisteredError < StandardError; end
    class WorksheetNotFoundError < Resource::ChildResourceNotFoundError; end
    class LastWorksheetCannotBeDeletedError < StandardError; end

    set_resource_type GoogleDrive::Spreadsheet

    class << self
      def has_many(resource, worksheet_name:, class_name:)
        register_worksheet_association(resource, worksheet_name: worksheet_name, class_name: class_name)
        create_worksheet_association(resource, worksheet_name: worksheet_name, class_name: class_name)
      end

      def register_worksheet_association(resource, worksheet_name:, class_name:)
        @associations ||= {}
        if @associations.fetch(resource, nil)
          raise WorksheetAssociationAlreadyRegisteredError
        end
        @associations[resource] = {
          worksheet_name: worksheet_name,
          class_name: class_name
        }
      end

      def create_worksheet_association(resource, **kwargs)
        define_method(resource) do
          worksheet_association(resource, **kwargs)
        end
      end
    end

    def find_association_by_id(association_name, id)
      find_associations_by_ids(association_name, [id]).first
    end

    def find_associations_by_ids(association_name, ids)
      send(association_name).find_by_ids(ids)
    end

    def find_associations_by_attribute(association_name, attribute_name, value)
      send(association_name).find_by_attribute(attribute_name, value)
    end

    def select_from_association(association_name, &block)
      send(association_name).select(&block)
    end

    def worksheet_association(association_name, worksheet_name:, class_name:)
      @associated_resources ||= {}
      @associated_resources[association_name] ||=
        find_or_create_worksheet!(title: worksheet_name, type: Support.constantize(class_name))
    end

    def worksheets
      @anonymous_resources ||= {}
      @anonymous_resources[:worksheets] ||= google_drive_resource.worksheets.map { |raw|
        set_up_worksheet!(google_drive_resource: raw)
      }
    end

    def set_up_worksheet!(google_drive_resource:, type: nil)
      wrap_worksheet(google_drive_resource: google_drive_resource, type: type).set_up!
    end

    def wrap_worksheet(google_drive_resource:, type: nil)
      Worksheet.new(
        google_drive_resource: google_drive_resource,
        spreadsheet: self,
        type: type
      )
    end

    def find_worksheet(title:, type: nil)
      find_worksheet!(title: title, type: type)
    rescue WorksheetNotFoundError
      nil
    end

    def find_worksheet!(title:, type: nil)
      find_and_setup_worksheet!(title: title, type: type, create: false)
    end

    def find_or_create_worksheet!(title:, type: nil)
      find_and_setup_worksheet!(title: title, type: type, create: true)
    end

    def find_and_setup_worksheet!(title:, type: nil, create: false)
      resource = google_drive_worksheet_by_title(title, create: create)
      set_up_worksheet!(google_drive_resource: resource, type: type)
    rescue ChildResourceNotFoundError
      raise WorksheetNotFoundError
    end

    def clean_up_default_worksheet!(force: false)
      default_sheet = google_drive_resource.worksheet_by_title("Sheet1")
      return unless default_sheet

      raise LastWorksheetCannotBeDeletedError if google_drive_resource.worksheets.count == 1

      wrap_worksheet(google_drive_resource: default_sheet).
        delete_google_drive_resource!(force: force)
    end

    def google_drive_worksheet_by_title(title, **kwargs)
      find_child_google_drive_resource_by(type: :worksheet, title: title, **kwargs)
    end
  end
end
