
require File.expand_path("../spec_helper", __dir__)

RSpec.describe SearchFlip::Connection do
  describe "#base_url" do
    it "returns the correct url" do
      expect(SearchFlip::Connection.new(base_url: "base url").base_url).to eq("base url")
    end
  end

  describe "#msearch" do
    it "sends multiple queries and returns all responses" do
      ProductIndex.import create(:product)
      CommentIndex.import create(:comment)

      responses = SearchFlip::Connection.new.msearch([ProductIndex.match_all, CommentIndex.match_all])

      expect(responses.size).to eq(2)
      expect(responses[0].total_entries).to eq(1)
      expect(responses[1].total_entries).to eq(1)
    end
  end

  describe "#update_aliases" do
    it "changes the aliases" do
      connection = SearchFlip::Connection.new

      connection.update_aliases(actions: [add: { index: "products", alias: "alias1" }])
      expect(connection.get_aliases(alias_name: "alias1").keys).to eq(["products"])

      connection.update_aliases(actions: [remove: { index: "products", alias: "alias1" }])
      expect(connection.alias_exists?("alias1")).to eq(false)
    end
  end

  describe "#get_aliases" do
    it "returns the specified aliases" do
      begin
        connection = SearchFlip::Connection.new

        connection.update_aliases(actions: [
          { add: { index: "comments", alias: "alias1" } },
          { add: { index: "products", alias: "alias2" } },
          { add: { index: "products", alias: "alias3" } }
        ])

        expect(connection.get_aliases.keys.to_set).to eq(["comments", "products"].to_set)
        expect(connection.get_aliases["products"]["aliases"].keys.to_set).to eq(["alias2", "alias3"].to_set)
        expect(connection.get_aliases["comments"]["aliases"].keys).to eq(["alias1"])
        expect(connection.get_aliases(index_name: "products").keys).to eq(["products"])
        expect(connection.get_aliases(index_name: "comments,products").keys.to_set).to eq(["comments", "products"].to_set)
        expect(connection.get_aliases(alias_name: "alias1,alias2").keys.to_set).to eq(["comments", "products"].to_set)
        expect(connection.get_aliases(alias_name: "alias1,alias2")["products"]["aliases"].keys).to eq(["alias2"])
      ensure
        connection.update_aliases(actions: [
          { remove: { index: "comments", alias: "alias1" } },
          { remove: { index: "products", alias: "alias2" } },
          { remove: { index: "products", alias: "alias3" } }
        ])
      end
    end
  end

  describe "#alias_exists?" do
    it "returns whether or not the specified alias exists?" do
      begin
        connection = SearchFlip::Connection.new

        expect(connection.alias_exists?(:some_alias)).to eq(false)

        connection.update_aliases(actions: [add: { index: "products", alias: "some_alias" }])

        expect(connection.alias_exists?(:some_alias)).to eq(true)
      ensure
        connection.update_aliases(actions: [remove: { index: "products", alias: "some_alias" }])
      end
    end
  end

  describe "#get_indices" do
    it "returns the specified indices" do
      connection = SearchFlip::Connection.new

      expect(connection.get_indices.map { |index| index["index"] }.to_set).to eq(["comments", "products"].to_set)
      expect(connection.get_indices("com*").map { |index| index["index"] }).to eq(["comments"])
    end
  end

  describe "#create_index" do
    it "creates the specified index" do
      begin
        connection = SearchFlip::Connection.new

        expect(connection.index_exists?("index_name")).to eq(false)

        connection.create_index("index_name")

        expect(connection.index_exists?("index_name")).to eq(true)
      ensure
        connection.delete_index("index_name") if connection.index_exists?("index_name")
      end
    end

    it "respects a payload" do
      connection = SearchFlip::Connection.new

      connection.create_index("index_name", settings: { number_of_shards: 3 })

      expect(connection.get_index_settings("index_name")["index_name"]["settings"]["index"]["number_of_shards"]).to eq("3")
    ensure
      connection.delete_index("index_name") if connection.index_exists?("index_name")
    end
  end

  describe "#close_index" do
    it "closes the specified index" do
      begin
        index = TestIndex.with_settings(index_name: "index_name")

        index.create_index
        index.import create(:product)
        index.open_index

        index.connection.close_index("index_name")

        expect(index.connection.get_indices("index_name").first["status"]).to eq("close")
      ensure
        index.delete_index if index.index_exists?
      end
    end
  end

  describe "#open_index" do
    it "opens the specified index" do
      begin
        index = TestIndex.with_settings(index_name: "index_name")

        index.create_index
        index.import create(:product)
        index.close_index

        index.connection.open_index("index_name")

        expect(index.connection.get_indices("index_name").first["status"]).to eq("open")
      ensure
        index.delete_index if index.index_exists?
      end
    end
  end

  describe "#update_index_settings" do
    it "updates the index settings" do
      begin
        connection = SearchFlip::Connection.new

        connection.create_index("index_name")
        connection.update_index_settings("index_name", settings: { number_of_replicas: 3 })

        expect(connection.get_index_settings("index_name")["index_name"]["settings"]["index"]["number_of_replicas"]).to eq("3")
      ensure
        connection.delete_index("index_name") if connection.index_exists?("index_name")
      end
    end
  end

  describe "#get_index_settings" do
    it "fetches the index settings" do
      begin
        connection = SearchFlip::Connection.new

        connection.create_index("index_name", settings: { number_of_shards: 3 })

        expect(connection.get_index_settings("index_name")["index_name"]["settings"]["index"]["number_of_shards"]).to eq("3")
      ensure
        connection.delete_index("index_name") if connection.index_exists?("index_name")
      end
    end
  end

  describe "#update_mapping" do
    it "updates the mapping of an index" do
      begin
        connection = SearchFlip::Connection.new

        mapping = { "type_name" => { "properties" => { "id" => { "type" => "long" } } } }

        connection.create_index("index_name")
        connection.update_mapping("index_name", "type_name", mapping)

        expect(connection.get_mapping("index_name", "type_name")).to eq("index_name" => { "mappings" => mapping })
      ensure
        connection.delete_index("index_name") if connection.index_exists?("index_name")
      end
    end
  end

  describe "#delete_index" do
    it "deletes the specified index" do
      begin
        connection = SearchFlip::Connection.new

        connection.create_index("index_name")
        expect(connection.index_exists?("index_name")).to eq(true)

        connection.delete_index("index_name")
        expect(connection.index_exists?("index_name")).to eq(false)
      ensure
        connection.delete_index("index_name") if connection.index_exists?("index_name")
      end
    end
  end

  describe "#refresh" do
    it "refreshes all or the specified indices" do
      begin
        connection = SearchFlip::Connection.new

        connection.create_index("index1")
        connection.create_index("index2")

        expect(connection.refresh).to be_truthy
        expect(connection.refresh("index1")).to be_truthy
        expect(connection.refresh(["index1", "index2"])).to be_truthy
      ensure
        connection.delete_index("index1") if connection.index_exists?("index1")
        connection.delete_index("index2") if connection.index_exists?("index2")
      end
    end
  end

  describe "#index_url" do
    it "returns the index url for the specified index" do
      connection = SearchFlip::Connection.new(base_url: "base_url")

      expect(connection.index_url("index_name")).to eq("base_url/index_name")
    end
  end

  describe "#type_url" do
    it "returns the type url for the specified index and type" do
      connection = SearchFlip::Connection.new(base_url: "base_url")

      expect(connection.type_url("index_name", "type_name")).to eq("base_url/index_name/type_name")
    end
  end
end

