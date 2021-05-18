require 'bigdecimal'

RSpec.describe SheetsDB::Worksheet do
  let(:raw_worksheet) {
    instance_double(GoogleDrive::Worksheet,
      rows: [
        ["id", "first_name", "", "last_name", "colors", "Food (Titleized)"],
        ["1", "Anna", "", "Scoofles", "", "pickles"],
        ["2", "Balaji", "n/a", "Rhutoni", "", "noodles"],
        ["3", "Snoof", "", "McDoorney", "", ""],
        ["4", "Anna", "", "Karenina", "", ""]
      ],
      num_rows: 5
    )
  }
  let(:row_class) { SheetsDB::Worksheet::Row }
  subject { described_class.new(spreadsheet: :the_spreadsheet, google_drive_resource: raw_worksheet, type: row_class) }

  describe "#attribute_at_row_position" do
    it "returns the value for the given attribute at the given row index" do
      allow(raw_worksheet).to receive(:[]).with(2, 2).and_return("Anna")
      allow(row_class).to receive(:attribute_definitions).and_return({ first_name: { transform: Proc.new { |val| val.upcase } } })
      expect(subject.attribute_at_row_position(:first_name, 2)).to eq("ANNA")
    end

    it "utilizes custom column name" do
      allow(raw_worksheet).to receive(:[]).with(2, 6).and_return("cabbage")
      allow(row_class).to receive(:attribute_definitions).and_return({ the_food: { column_name: "Food (Titleized)" } })
      expect(subject.attribute_at_row_position(:the_food, 2)).to eq("cabbage")
    end

    it "converts the given value according to type" do
      allow(raw_worksheet).to receive(:[]).with(2, 2).and_return("Anna")
      allow(row_class).to receive(:attribute_definitions).and_return({ first_name: { type: :the_type } })
      allow(subject).to receive(:convert_value).with("Anna", { type: :the_type }).and_return("Deanna")
      expect(subject.attribute_at_row_position(:first_name, 2)).to eq("Deanna")
    end

    it "converts the given value according to type" do
      allow(raw_worksheet).to receive(:[]).with(2, 2).and_return("Anna")
      allow(row_class).to receive(:attribute_definitions).and_return({ first_name: { type: :the_type } })
      allow(subject).to receive(:convert_value).with("Anna", { type: :the_type }).and_return("Deanna")
      expect(subject.attribute_at_row_position(:first_name, 2)).to eq("Deanna")
    end

    it "splits multiple return values" do
      allow(raw_worksheet).to receive(:[]).with(2, 2).and_return("Anna, Banana")
      allow(row_class).to receive(:attribute_definitions).and_return({ first_name: { type: :the_type, multiple: true } })
      allow(subject).to receive(:convert_value).with("Anna", { type: :the_type, multiple: true }).and_return("Deanna")
      allow(subject).to receive(:convert_value).with("Banana", { type: :the_type, multiple: true }).and_return("The Banana")
      expect(subject.attribute_at_row_position(:first_name, 2)).to eq(["Deanna", "The Banana"])
    end

    it "reads input values directly if type is DateTime" do
      allow(raw_worksheet).to receive(:input_value).with(2, 2).and_return("April 15")
      allow(row_class).to receive(:attribute_definitions).and_return({ first_name: { type: DateTime } })
      allow(subject).to receive(:convert_value).with("April 15", { type: DateTime }).and_return("4/15")
      expect(subject.attribute_at_row_position(:first_name, 2)).to eq("4/15")
    end

    it "returns value_if_column_missing if column not found" do
      allow(row_class).to receive(:attribute_definitions).and_return({ first_name: { column_name: "Wrong Column" } })
      allow(subject).to receive(:value_if_column_missing).with({ column_name: "Wrong Column" }).and_return(:the_missing_value)
      expect(subject.attribute_at_row_position(:first_name, 2)).to eq(:the_missing_value)
    end
  end

  describe "#value_if_column_missing" do
    it "raises a ColumnNotFoundError if no if_column_missing proc" do
      definition = { column_name: "Wrong Column" }
      expect {
        subject.value_if_column_missing(definition)
      }.to raise_error(described_class::ColumnNotFoundError, "Wrong Column")
    end

    it "returns results of if_column_missing proc" do
      row_class.attribute :wow
      definition = {
        column_name: "Wrong Column",
        if_column_missing: Proc.new { wow }
      }
      allow(subject).to receive(:wow).and_return(:the_missing_value)
      expect(subject.value_if_column_missing(definition)).to eq(:the_missing_value)
    end
  end

  describe "#update_attributes_at_row_position" do
    it "updates the given attributes using the google drive resource" do
      allow(row_class).to receive(:attribute_definitions).and_return({
        first_name: {},
        last_name: {},
        colors: { multiple: true },
        the_food: { column_name: "Food (Titleized)" }
      })
      expect(raw_worksheet).to receive(:[]=).with(2, 2, "Bonnie")
      expect(raw_worksheet).to receive(:[]=).with(2, 4, "McFragile")
      expect(raw_worksheet).to receive(:[]=).with(2, 5, "green,white")
      expect(raw_worksheet).to receive(:[]=).with(2, 6, "tasties")
      expect(raw_worksheet).to receive(:synchronize)
      subject.update_attributes_at_row_position({ first_name: "Bonnie", last_name: "McFragile", colors: ["green", "white"], the_food: "tasties" }, row_position: 2)
    end

    it "updates given attributes but does not synchronize if delaying sync" do
      allow(subject).to receive(:synchronizing).and_return(false)
      allow(row_class).to receive(:attribute_definitions).and_return({ first_name: {} })
      expect(raw_worksheet).to receive(:[]=).with(2, 2, "Bonnie")
      expect(raw_worksheet).not_to receive(:synchronize)
      subject.update_attributes_at_row_position({ first_name: "Bonnie" }, row_position: 2)
    end

    it "raises a ColumnNotFoundError if accessing a column that does not exist" do
      allow(row_class).to receive(:attribute_definitions).and_return({ first_name: { column_name: "Wrong Column" } })
      expect {
        subject.update_attributes_at_row_position({ first_name: "Bonnie" }, row_position: 2)
      }.to raise_error(described_class::ColumnNotFoundError)
    end
  end

  describe "#new" do
    let(:new_row) { instance_double(SheetsDB::Worksheet::Row) }

    it "returns new instance of type with unset row_position" do
      allow(row_class).to receive(:new).with(worksheet: subject, row_position: nil).
        and_return(new_row)
      allow(new_row).to receive(:stage_attributes).with({})
      expect(subject.new).to eq(new_row)
    end

    it "pre-stages given attributes on new row" do
      allow(row_class).to receive(:new).with(worksheet: subject, row_position: nil).
        and_return(new_row)
      allow(new_row).to receive(:stage_attributes).with({ foo: :bar })
      expect(subject.new(foo: :bar)).to eq(new_row)
    end
  end

  describe "#create!" do
    it "returns #new row after calling #save!" do
      new_row = instance_double(SheetsDB::Worksheet::Row)
      allow(subject).to receive(:new).with(foo: :bar).and_return(new_row)
      allow(new_row).to receive(:save!).and_return(:saved_row)
      expect(subject.create!(foo: :bar)).to eq(:saved_row)
    end
  end

  describe "#import!" do
    it "in transaction, creates records for each set of attributes in given array" do
      expect(subject).to receive(:disable_synchronization!).ordered
      expect(subject).to receive(:create!).with(foo: :bar).ordered
      expect(subject).to receive(:create!).with(baz: :narf).ordered
      expect(raw_worksheet).to receive(:synchronize).ordered
      expect(subject).to receive(:enable_synchronization!).ordered
      subject.import!([{ foo: :bar }, { baz: :narf }])
    end
  end

  describe "#all" do
    it "returns instances of type for each row in worksheet" do
      allow(row_class).to receive(:new).with(worksheet: subject, row_position: 2).
        and_return(:row_2)
      allow(row_class).to receive(:new).with(worksheet: subject, row_position: 3).
        and_return(:row_3)
      allow(row_class).to receive(:new).with(worksheet: subject, row_position: 4).
        and_return(:row_4)
      allow(row_class).to receive(:new).with(worksheet: subject, row_position: 5).
        and_return(:row_5)
      expect(subject.all).to eq([:row_2, :row_3, :row_4, :row_5])
    end
  end

  describe "#find_by_id" do
    it "returns row with given id" do
      allow(subject).to receive(:find_by_ids).with([2]).and_return([:result])
      expect(subject.find_by_id(2)).to eq(:result)
    end

    it "returns nil if id not found" do
      allow(subject).to receive(:find_by_ids).with([2]).and_return([])
      expect(subject.find_by_id(2)).to be_nil
    end
  end

  describe "#find_by_ids" do
    it "returns rows with given ids" do
      row_class.attribute :id, type: Integer

      allow(raw_worksheet).to receive(:[]).with(2, 1).and_return("1")
      allow(raw_worksheet).to receive(:[]).with(3, 1).and_return("2")
      allow(raw_worksheet).to receive(:[]).with(4, 1).and_return("3")
      expect(subject.find_by_ids([2, 3]).map(&:row_position)).to eq([3, 4])
    end
  end

  describe "#find_by_attribute" do
    it "returns rows with matching attribute value" do
      row_class.attribute :first_name

      allow(raw_worksheet).to receive(:[]).with(2, 2).and_return("Anna")
      allow(raw_worksheet).to receive(:[]).with(3, 2).and_return("Frank")
      allow(raw_worksheet).to receive(:[]).with(4, 2).and_return("Parker")
      allow(raw_worksheet).to receive(:[]).with(5, 2).and_return("Anna")
      expect(subject.find_by_attribute(:first_name, "Anna").map(&:row_position)).to eq([2, 5])
    end
  end

  describe "#columns" do
    it "returns columns with names and positions" do
      expect(subject.columns).to eq({
        "id" => SheetsDB::Worksheet::Column.new(name: "id", column_position: 1),
        "first_name" => SheetsDB::Worksheet::Column.new(name: "first_name", column_position: 2),
        "last_name" => SheetsDB::Worksheet::Column.new(name: "last_name", column_position: 4),
        "colors" => SheetsDB::Worksheet::Column.new(name: "colors", column_position: 5),
        "Food (Titleized)" => SheetsDB::Worksheet::Column.new(name: "Food (Titleized)", column_position: 6)
      })
    end
  end

  describe "#column_names" do
    it "returns column names" do
      expect(subject.column_names).to eq([
        "id",
        "first_name",
        "last_name",
        "colors",
        "Food (Titleized)"
      ])
    end
  end


  describe "#reload!" do
    it "reloads the google_drive_resource worksheet" do
      expect(raw_worksheet).to receive(:reload)
      subject.reload!
    end
  end

  describe "#convert_value" do
    it "returns nil if given a blank string" do
      expect(subject.convert_value("", { type: :whatever })).to be_nil
    end

    it "returns stripped value if unrecognized type" do
      expect(subject.convert_value("  a string ", { type: :whatever })).to eq("a string")
    end

    it "returns unstripped value if strip is false" do
      expect(subject.convert_value("  a string ", { strip: false, type: :whatever })).to eq("  a string ")
    end

    it "returns integer value if type is Integer" do
      expect(subject.convert_value("14", { type: Integer })).to eq(14)
    end

    it "returns BigDecimal value if type is Decimal" do
      expect(subject.convert_value("1.54", { type: :Decimal })).to eq(BigDecimal.new("1.54"))
    end

    it "returns DateTime value if type is DateTime" do
      expect(subject.convert_value("4/15/2016 10:15:30", { type: DateTime })).to eq(
        DateTime.parse("2016-04-15 10:15:30")
      )
    end

    context "when type is Boolean" do
      it "returns results of calling #convert_to_boolean with raw_value" do
        allow(subject).to receive(:convert_to_boolean).with("the_value").and_return(:a_result)
        expect(subject.convert_value("the_value", { type: :Boolean })).to eq(:a_result)
      end
    end
  end

  describe "#convert_to_boolean" do
    it "returns true if value in truthy list" do
      expect(subject.convert_to_boolean("Y")).to eq(true)
      expect(subject.convert_to_boolean("Yes")).to eq(true)
      expect(subject.convert_to_boolean("true")).to eq(true)
      expect(subject.convert_to_boolean("1")).to eq(true)
    end

    it "returns false if value in falsy list" do
      expect(subject.convert_to_boolean("n")).to eq(false)
      expect(subject.convert_to_boolean("NO")).to eq(false)
      expect(subject.convert_to_boolean("fALSE")).to eq(false)
      expect(subject.convert_to_boolean("0")).to eq(false)
    end

    it "returns nil if the value is not in truthy or falsy lists" do
      expect(subject.convert_to_boolean(nil)).to be_nil
      expect(subject.convert_to_boolean("whatever")).to be_nil
      expect(subject.convert_to_boolean("")).to be_nil
    end
  end

  describe "#==" do
    it "returns true if google drive resource is the same and type is the same" do
      expect(subject).to eq(
        described_class.new(spreadsheet: :the_spreadsheet, google_drive_resource: raw_worksheet, type: row_class)
      )
    end

    it "returns false if other is not the same class" do
      expect(subject).not_to eq(
        SheetsDB::Spreadsheet.new(google_drive_resource: raw_worksheet)
      )
    end

    it "returns false if google drive resource is the same but type is different" do
      expect(subject).not_to eq(
        described_class.new(spreadsheet: :the_spreadsheet, google_drive_resource: raw_worksheet, type: :other)
      )
    end

    it "returns false if google drive resource is different" do
      expect(subject).not_to eq(
        described_class.new(spreadsheet: :the_spreadsheet, google_drive_resource: :whatever, type: row_class)
      )
    end
  end

  describe "#eql?" do
    it "aliases to ==" do
      expect(subject.method(:eql?)).to eq(subject.method(:==))
    end
  end

  describe "#hash" do
    it "returns hash of class, worksheet, and row position" do
      expect(subject.hash).to eq(
        [described_class, raw_worksheet, row_class].hash
      )
    end
  end

  describe "#next_available_row_position" do
    it "returns worksheet's row count + 1" do
      allow(raw_worksheet).to receive(:num_rows).and_return(6)
      expect(subject.next_available_row_position).to eq(7)
    end
  end

  describe "#transaction" do
    it "yields to given block with synchronizing set to false" do
      expect(subject).to receive(:disable_synchronization!).ordered
      expect(subject).to receive(:reload!).ordered
      expect(raw_worksheet).to receive(:synchronize).ordered
      expect(subject).to receive(:enable_synchronization!).ordered

      subject.transaction do
        subject.reload!
      end
    end

    it "does not synchronize, but restores synchronizing to true, if exception thrown" do
      expect(subject).to receive(:disable_synchronization!).ordered
      expect(raw_worksheet).not_to receive(:synchronize)
      expect(subject).to receive(:enable_synchronization!).ordered
      expect {
        subject.transaction do
          raise ArgumentError
        end
      }.to raise_error(ArgumentError)
    end
  end

  describe "#disable_synchronization!" do
    it "sets synchronizing to false" do
      expect(subject.synchronizing).to eq(true)
      subject.disable_synchronization!
      expect(subject.synchronizing).to eq(false)
    end
  end

  describe "#enable_synchronization!" do
    it "sets synchronizing to true" do
      subject.disable_synchronization!
      expect(subject.synchronizing).to eq(false)
      subject.enable_synchronization!
      expect(subject.synchronizing).to eq(true)
    end
  end
end
