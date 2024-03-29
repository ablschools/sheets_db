module SheetsDB
  class Worksheet
    class Row
      class AttributeAlreadyRegisteredError < StandardError; end
      class AssociationAlreadyRegisteredError < StandardError; end

      class << self
        def inherited(subclass)
          super
          subclass.instance_variable_set(
            :@attribute_definitions,
            Marshal.load(Marshal.dump(@attribute_definitions))
          )
        end

        def attribute(name, type: String, multiple: false, transform: nil, column_name: nil, aliases: [], if_column_missing: nil)
          register_attribute(name, type: type, multiple: multiple, transform: transform, column_name: (column_name || name).to_s, association: false, aliases: aliases, if_column_missing: if_column_missing)

          define_method(name) do
            begin
              get_modified_attribute(name)
            rescue KeyError
              get_persisted_attribute(name)
            end
          end

          define_method("#{name}=") do |value|
            stage_attribute_modification(name, value)
          end
        end

        def has_association(name, from_collection:, key:, multiple: false)
          register_attribute(name, from_collection: from_collection, key: key, multiple: multiple, association: true)

          define_method(name) do
            @loaded_associations[name] ||= begin
              response = spreadsheet.find_associations_by_ids(from_collection, Array(send(key)))
              multiple ? response : response.first
            end
          end

          define_method("#{name}=") do |value|
            assignment_value = multiple ? value.map(&:id) : value.id
            send("#{key}=", assignment_value)
            @loaded_associations[name] = value
          end
        end

        def has_one(name, from_collection:, key:)
          has_association(name, from_collection: from_collection, key: key, multiple: false)
        end

        def has_many(name, from_collection:, key:)
          has_association(name, from_collection: from_collection, key: key, multiple: true)
        end

        def belongs_to_association(name, from_collection:, foreign_key:, multiple: false)
          register_attribute(name, from_collection: from_collection, foreign_key: foreign_key, multiple: multiple, association: true)

          define_method(name) do
            @loaded_associations[name] ||= begin
              response = spreadsheet.find_associations_by_attribute(from_collection, foreign_key, id)
              multiple ? response : response.first
            end
          end

          define_method("#{name}=") do |value|
            existing_values = Array(send(name))
            Array(value).each do |foreign_item|
              next if existing_values.delete(foreign_item)
              foreign_item.add_element_to_attribute(foreign_key, id)
              @changed_foreign_items << foreign_item
            end
            existing_values.each do |existing_foreign_item|
              existing_foreign_item.remove_element_from_attribute(foreign_key, id)
              @changed_foreign_items << existing_foreign_item
            end
            @loaded_associations[name] = value
          end
        end

        def belongs_to_one(name, from_collection:, foreign_key:)
          belongs_to_association(name, from_collection: from_collection, foreign_key: foreign_key, multiple: false)
        end

        def belongs_to_many(name, from_collection:, foreign_key:)
          belongs_to_association(name, from_collection: from_collection, foreign_key: foreign_key, multiple: true)
        end

        def register_attribute(name, **options)
          if attribute_definitions.fetch(name, nil)
            raise AttributeAlreadyRegisteredError, name
          end
          attribute_definitions[name] = options
        end

        def attribute_definitions
          @attribute_definitions ||= {}
        end

        def association_definitions
          attribute_definitions.select { |_, value| value[:association] }
        end
      end

      attr_reader :worksheet, :row_position, :loaded_attributes, :loaded_associations, :changed_foreign_items

      def initialize(worksheet:, row_position:)
        @worksheet = worksheet
        @row_position = row_position
        @loaded_attributes = {}
        @loaded_associations = {}
        @changed_foreign_items = []
      end

      def column_names
        worksheet.column_names
      end

      def new_row?
        row_position.nil?
      end

      def get_modified_attribute(name)
        loaded_attributes.fetch(name, {}).
          fetch(:changed)
      end

      def get_persisted_attribute(name)
        loaded_attributes[name] ||= {}
        loaded_attributes[name][:original] ||=
          worksheet.attribute_at_row_position(name, row_position)
      end

      def stage_attribute_modification(name, value)
        loaded_attributes[name] ||= {}
        loaded_attributes[name][:changed] = value
      end

      def stage_attributes(new_attribute_set)
        new_attribute_set.each do |name, value|
          send(:"#{name}=", value)
        end
      end

      def update_attributes!(new_attribute_set)
        stage_attributes(new_attribute_set)
        save!
      end

      def modify_collection_attribute(name, value, remove:)
        attribute_definition = self.class.attribute_definitions.fetch(name, {})
        existing_value = Array(send(name))
        return if remove && !existing_value.include?(value)
        return if !remove && existing_value.include?(value)
        assignment_value = if attribute_definition[:multiple]
          remove ? existing_value - [value] : existing_value.concat([value])
        else
          remove ? nil : value
        end
        send("#{name}=", assignment_value)
      end

      def add_element_to_attribute(name, value)
        modify_collection_attribute(name, value, remove: false)
      end

      def remove_element_from_attribute(name, value)
        modify_collection_attribute(name, value, remove: true)
      end

      def reload!
        worksheet.reload!
        reset_attributes_and_associations_cache
        self
      end

      def save!
        assign_next_row_position_if_not_set
        worksheet.update_attributes_at_row_position(staged_attributes, row_position: row_position)
        save_changed_foreign_items!
        reset_attributes_and_associations_cache
        self
      end

      def assign_next_row_position_if_not_set
        @row_position ||= worksheet.next_available_row_position
      end

      def save_changed_foreign_items!
        changed_foreign_items.each(&:save!)
      end

      def reset_attributes_and_associations_cache
        @loaded_attributes = {}
        @loaded_associations = {}
        self
      end

      def staged_attributes
        loaded_attributes.each_with_object({}) { |(key, value), hsh|
          next unless value
          hsh[key] = value[:changed] if value[:changed]
          hsh
        }
      end

      def spreadsheet
        worksheet.spreadsheet
      end

      def attributes
        get_all_attributes do |options|
          !options.fetch(:association, false)
        end
      end

      def associations
        get_all_attributes do |options|
          options.fetch(:association, false)
        end
      end

      def get_all_attributes(&block)
        self.class.attribute_definitions.each_with_object({}) { |(name, options), memo|
          memo[name] = send(name) if block.call(options)
          memo
        }
      end

      def to_hash(depth: 0)
        hashed_associations = if depth > 0
          Hash[
            associations.map { |name, association|
              association_hash = if association.is_a?(Array)
                association.map { |item| item.to_hash(depth: depth - 1) }
              else
                association.to_hash(depth: depth - 1)
              end
              [name, association_hash]
            }
          ]
        else
          {}
        end
        attributes.merge(hashed_associations)
      end

      def ==(other)
        other.is_a?(self.class) &&
          other.worksheet == worksheet &&
          other.row_position == row_position
      end

      alias_method :eql?, :==

      def hash
        [self.class, worksheet, row_position].hash
      end
    end
  end
end
