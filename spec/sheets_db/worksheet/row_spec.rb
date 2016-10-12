RSpec.describe SheetsDB::Worksheet::Row do
  let(:row_class) { Class.new(described_class) }
  let(:worksheet) { SheetsDB::Worksheet.new(spreadsheet: :a_spreadsheet, google_drive_resource: :a_worksheet, type: row_class) }
  subject { row_class.new(worksheet: worksheet, row_position: 3) }

  describe ".attribute" do  
    before(:each) do
      allow(worksheet).to receive(:attribute_at_row_position).with(:foo, row_position: 3).once.and_return("1")
      allow(worksheet).to receive(:attribute_at_row_position).with(:things, row_position: 3).and_return("1,2, 3")
    end

    context "with basic attribute" do
      before(:each) do
        allow(subject).to receive(:convert_value).with("1", String).and_return("the_number_1")
        row_class.attribute :foo
      end

      it "sets up memoized reader for attribute, with String conversion" do
        subject.foo
        expect(subject.foo).to eq("the_number_1")
      end

      it "returns staged change if exists" do
        subject.attributes[:foo] = { changed: "a_new_number" }
        expect(subject.foo).to eq("a_new_number")
      end

      it "sets up writer for attribute that stages change but doesn't persist it" do
        subject.foo = "a_new_number"
        expect(subject.attributes[:foo][:changed]).to eq("a_new_number")
        allow(worksheet).to receive(:reload!)
        subject.reload!
        expect(subject.foo).to eq("the_number_1")
      end
    end

    context "with type specification" do
      before(:each) do
        row_class.attribute :foo, type: :the_type
      end

      it "sets up reader for attribute, with type conversion" do
        allow(subject).to receive(:convert_value).with("1", :the_type).and_return("the_number_1")
        expect(subject.foo).to eq("the_number_1")
      end
    end

    context "with collection attribute" do
      before(:each) do
        row_class.attribute :things, type: :the_type, collection: true
      end

      it "sets up reader for attribute, with type conversion" do
        allow(subject).to receive(:convert_value).with("1", :the_type).and_return(1)
        allow(subject).to receive(:convert_value).with("2", :the_type).and_return(2)
        allow(subject).to receive(:convert_value).with("3", :the_type).and_return(3)
        expect(subject.things).to eq([1, 2, 3])
      end
    end
  end

  describe "#convert_value" do
    it "returns nil if given a blank string" do
      expect(subject.convert_value("", :whatever)).to be_nil
    end

    it "returns given value if unrecognized type" do
      expect(subject.convert_value("something", :whatever)).to eq("something")
    end

    it "returns integer value if type is Integer" do
      expect(subject.convert_value("14", Integer)).to eq(14)
    end
  end

  describe "#staged_attributes" do
    it "returns hash of staged attribute names and values" do
      allow(subject).to receive(:attributes).and_return({
        foo: {},
        bar: { original: 11, changed: nil },
        baz: { original: 6, changed: 14 },
        nerf: { changed: 45 }
      })
      expect(subject.staged_attributes).to eq({ baz: 14, nerf: 45 })
    end
  end

  describe "#reset_attributes_and_associations_cache" do
    it "clears the associations and attributes caches" do
      subject.instance_variable_set(:@attributes, :some_attributes)
      subject.instance_variable_set(:@associations, :some_associations)
      subject.reset_attributes_and_associations_cache
      expect(subject.attributes).to be_empty
      expect(subject.associations).to be_empty
    end
  end

  describe "#save!" do
    it "updates staged attributes on worksheet and empties attribute and association cache" do
      allow(subject).to receive(:staged_attributes).and_return(:the_staged_attributes)
      expect(worksheet).to receive(:update_attributes_at_row_position).
        with(:the_staged_attributes, row_position: 3).ordered
      expect(subject).to receive(:reset_attributes_and_associations_cache).ordered
      subject.save!
    end
  end
end
