
# SearchFlip

**Full-Featured ElasticSearch Ruby Client with a Chainable DSL**

[![Build Status](https://secure.travis-ci.org/mrkamel/search_flip.png?branch=master)](http://travis-ci.org/mrkamel/search_flip)
[![Gem Version](https://badge.fury.io/rb/search_flip.svg)](http://badge.fury.io/rb/search_flip)

Using SearchFlip it is dead-simple to create index classes that correspond to
[ElasticSearch](https://www.elastic.co/) indices and to manipulate, query and
aggregate these indices using a chainable, concise, yet powerful DSL. Finally,
SearchFlip supports ElasticSearch 1.x, 2.x, 5.x, 6.x, 7.x. Check section
[Feature Support](#feature-support) for version dependent features.

```ruby
CommentIndex.search("hello world", default_field: "title").where(visible: true).aggregate(:user_id).sort(id: "desc")

CommentIndex.aggregate(:user_id) do |aggregation|
  aggregation.aggregate(histogram: { date_histogram: { field: "created_at", interval: "month" }})
end

CommentIndex.range(:created_at, gt: Date.today - 1.week, lt: Date.today).where(state: ["approved", "pending"])
```

## Updating from previous SearchFlip versions

Checkout [UPDATING.md](./UPDATING.md) for detailed instructions.

## Comparison with other gems

There are great ruby gems to work with Elasticsearch like e.g. searchkick and
elasticsearch-ruby already. However, they don't have a chainable API. Compare
yourself.

```ruby
# elasticsearch-ruby
Comment.search(
  query: {
    query_string: {
      query: "hello world",
      default_operator: "AND"
    }
  }
)

# searchkick
Comment.search("hello world", where: { available: true }, order: { id: "desc" }, aggs: [:username])

# search_flip
CommentIndex.where(available: true).search("hello world").sort(id: "desc").aggregate(:username)

```

Finally, SearchFlip comes with a minimal set of dependencies (http-rb, hashie
and oj only).

## Reference Docs

SearchFlip has a great documentation.
Check youself at [http://www.rubydoc.info/github/mrkamel/search_flip](http://www.rubydoc.info/github/mrkamel/search_flip)

## Install

Add this line to your application's Gemfile:

```ruby
gem 'search_flip'
```

and then execute

```
$ bundle
```

or install it via

```
$ gem install search_flip
```

## Config

You can change global config options like:

```ruby
SearchFlip::Config[:environment] = "development"
SearchFlip::Config[:base_url] = "http://127.0.0.1:9200"
```

Available config options are:

* `index_prefix` to have a prefix added to your index names automatically. This
  can be useful to separate the indices of e.g. testing and development environments.
* `base_url` to tell SearchFlip how to connect to your cluster
* `bulk_limit` a global limit for bulk requests
* `bulk_max_mb` a global limit for the payload of bulk requests
* `auto_refresh` tells SearchFlip to automatically refresh an index after
  import, index, delete, etc operations. This is e.g. usuful for testing, etc.
  Defaults to false.

## Usage

First, create a separate class for your index and include `SearchFlip::Index`.

```ruby
class CommentIndex
  include SearchFlip::Index
end
```

Then tell the Index about the index name, the correspoding model and how to
serialize the model for indexing.

```ruby
class CommentIndex
  include SearchFlip::Index

  def self.index_name
    "comments"
  end

  def self.model
    Comment
  end

  def self.serialize(comment)
    {
      id: comment.id,
      username: comment.username,
      title: comment.title,
      message: comment.message
    }
  end
end
```

Optionally, you can specify a custom `type_name`, but note that starting with
Elasticsearch 7, types are deprecated.

```ruby
class CommentIndex
  # ...

  def self.type_name
    "comment"
  end
end
```

You can additionally specify an `index_scope` which will automatically be
applied to scopes, eg. ActiveRecord::Relation objects, passed to `#import`,
`#index`, etc. This can be used to preload associations that are used when
serializing records or to restrict the records you want to index.

```ruby
class CommentIndex
  # ...

  def self.index_scope(scope)
    scope.preload(:user)
  end
end

CommentIndex.import(Comment.all) # => CommentIndex.import(Comment.all.preload(:user))
```

To specify a custom mapping:

```ruby
class CommentIndex
  # ...

  def self.mapping
    {
      properties: {
        # ...
      }
    }
  end

  # ...
end
```

Please note that you need to specify the mapping without a type name, even for
Elasticsearch versions before 7, as SearchFlip will add the type name
automatically if neccessary.

To specify index settings:

```ruby
def self.index_settings
  {
    settings: {
      number_of_shards: 10,
      number_of_replicas: 2
    }
  }
end
```

Then you can interact with the index:

```ruby
CommentIndex.create_index
CommentIndex.index_exists?
CommentIndex.delete_index
CommentIndex.update_mapping
CommentIndex.close_index
CommentIndex.open_index
```

index records (automatically uses the bulk API):

```ruby
CommentIndex.import(Comment.all)
CommentIndex.import(Comment.first)
CommentIndex.import([Comment.find(1), Comment.find(2)])
CommentIndex.import(Comment.where("created_at > ?", Time.now - 7.days))
```

query records:

```ruby
CommentIndex.total_entries
# => 2838

CommentIndex.search("title:hello").records
# => [#<Comment ...>, #<Comment ...>, ...]

CommentIndex.where(username: "mrkamel").total_entries
# => 13

CommentIndex.aggregate(:username).aggregations(:username)
# => {1=>#<SearchFlip::Result doc_count=37 ...>, 2=>... }
...

CommentIndex.search("hello world").sort(id: "desc").aggregate(:username).request
# => {:query=>{:bool=>{:must=>[{:query_string=>{:query=>"hello world", :default_operator=>:AND}}]}}, ...}
```

delete records:

```ruby
# for ElasticSearch >= 2.x and < 5.x, the delete-by-query plugin is required
# for the following query:

CommentIndex.match_all.delete

# or delete manually via the bulk API:

CommentIndex.bulk do |indexer|
  CommentIndex.match_all.find_each do |record|
    indexer.delete record.id
  end
end
```

## Working with Elasticsearch Aliases

You can use and manage Elasticsearch Aliases like the following:

```ruby
class UserIndex
  include SearchFlip::Index

  def self.index_name
    alias_name
  end

  def self.alias_name
    "users"
  end
end
```

Then, create an index, import the records and add the alias like:

```ruby
new_user_index = UserIndex.with_settings(index_name: "users-#{SecureRandom.hex}")
new_user_index.create_index
new_user_index.import User.all
new_user.connection.update_aliases(actions: [
  add: { index: new_user_index.index_name, alias: new_user_index.alias_name }
])
```

If the alias already exists, you of course have to remove it as well first
within `update_aliases`.

Please note that `with_settings(index_name: '...')` returns an anonymous, i.e.
temporary, class inherting from UserIndex and overwriting `index_name`.

## Chainable Methods

SearchFlip supports even more advanced usages, like e.g. post filters, filtered
aggregations or nested aggregations via simple to use API methods.

### Query/Filter Criteria Methods

SearchFlip provides powerful methods to query/filter Elasticsearch:

* `where`

Feels like ActiveRecord's `where` and adds a bool filter clause to the request:

```ruby
CommentIndex.where(reviewed: true)
CommentIndex.where(likes: 0 .. 10_000)
CommentIndex.where(state: ["approved", "rejected"])
```

* `where_not`

Like `where`, but exluding the matching documents:

```ruby
CommentIndex.where_not(id: [1, 2, 3])
```

* `range`

To add a range filter query:

```ruby
CommentIndex.range(:created_at, gt: Date.today - 1.week, lt: Date.today)
```

* `filter`

Use `filter` to add raw filter queries:

```ruby
CommentIndex.filter(term: { state: "approved" })
```

* `should`

Use `should` to add raw should queries:

```ruby
CommentIndex.should(term: { state: "approved" })
```

* `must`

Use `must` to add raw must queries:

```ruby
CommentIndex.must(term: { state: "approved" })

CommentIndex.must(
  bool: {
    should: [
      { terms: { state: ["approved", "rejected"] }},
      { term: { username: "mrkamel" }}
    ]
  }
)
```

* `must_not`

Like `must`, but excluding the matching documents:

```ruby
CommentIndex.must_not(term: { state: "approved" })
```

* `search`

Adds a query string query, with AND as default operator:

```ruby
CommentIndex.search("hello world")
CommentIndex.search("state:approved")
CommentIndex.search("username:a*")
CommentIndex.search("state:approved OR state:rejected")
CommentIndex.search("hello world", default_operator: "OR")
```

* `exists`

Use `exists` to add an `exists` query:

```ruby
CommentIndex.exists(:state)
```

* `exists_not`

Like `exists`, but excluding the matching documents:

```ruby
CommentIndex.exists_not(:state)
```

* `match_all`

Simply matches all documents:

```ruby
CommentIndex.match_all
```

### Post Query/Filter Criteria Methods

All query/filter criteria methods (`#where`, `#where_not`, `#range`, etc.) are available
in post filter mode as well, ie. filters/queries applied after aggregations
are calculated. Checkout the ElasticSearch docs for further info.

```ruby
query = CommentIndex.aggregate(:user_id)
query = query.post_where(reviewed: true)
query = query.post_search("username:a*")
```

Checkout [PostFilterable](http://www.rubydoc.info/github/mrkamel/search_flip/SearchFlip/PostFilterable)
for a complete API reference.

### Aggregations

SearchFlip allows to elegantly specify nested aggregations, no matter how deeply
nested:

```ruby
query = OrderIndex.aggregate(:username, order: { revenue: "desc" }) do |aggregation|
  aggregation.aggregate(revenue: { sum: { field: "price" }})
end
```

Generally, aggregation results returned by ElasticSearch are returned as a
`SearchFlip::Result`, which basically is `Hashie::Mash`such that you can access
them via:

```ruby
query.aggregations(:username)["mrkamel"].revenue.value
```

Still, if you want to get the raw aggregations returned by ElasticSearch,
access them without supplying any aggregation name to `#aggregations`:

```ruby
query.aggregations # => returns the raw aggregation section

query.aggregations["username"]["buckets"].detect { |bucket| bucket["key"] == "mrkamel" }["revenue"]["value"] # => 238.50
```

Once again, the criteria methods (`#where`, `#range`, etc.) are available in
aggregations as well:

```ruby
query = OrderIndex.aggregate(average_price: {}) do |aggregation|
  aggregation = aggregation.match_all
  aggregation = aggregation.where(user_id: current_user.id) if current_user

  aggregation.aggregate(average_price: { avg: { field: "price" }})
end

query.aggregations(:average_price).average_price.value
```

Checkout [Aggregatable](http://www.rubydoc.info/github/mrkamel/search_flip/SearchFlip/Aggregatable)
as well as [Aggregation](http://www.rubydoc.info/github/mrkamel/search_flip/SearchFlip/Aggregation)
for a complete API reference.

### Suggestions

```ruby
query = CommentIndex.suggest(:suggestion, text: "helo", term: { field: "message" })
query.suggestions(:suggestion).first["text"] # => "hello"
```

### Highlighting

```ruby
CommentIndex.highlight([:title, :message])
CommentIndex.highlight(:title).highlight(:description)
CommentIndex.highlight(:title, require_field_match: false)
CommentIndex.highlight(title: { type: "fvh" })
```

```ruby
query = CommentIndex.highlight(:title).search("hello")
query.results[0]._hit.highlight.title # => "<em>hello</em> world"
```

### Other Criteria Methods

There are even more chainable criteria methods to make your life easier. For a
full list, checkout the reference docs.

* `source`

In case you want to restrict the returned fields, simply specify
the fields via `#source`:

```ruby
CommentIndex.source([:id, :message]).search("hello world")
```

* `paginate`, `page`, `per`

SearchFlip supports
[will_paginate](https://github.com/mislav/will_paginate) and
[kaminari](https://github.com/kaminari/kaminari) compatible pagination. Thus,
you can either use `#paginate` or `#page` in combination with `#per`:

```ruby
CommentIndex.paginate(page: 3, per_page: 50)
CommentIndex.page(3).per(50)
```

* `profile`

Use `#profile` to enable query profiling:

```ruby
query = CommentIndex.profile(true)
query.raw_response["profile"] # => { "shards" => ... }
```

* `preload`, `eager_load` and `includes`

Uses the well known methods from ActiveRecord to load
associated database records when fetching the respective
records themselves. Works with other ORMs as well, if
supported.

Using `#preload`:

```ruby
CommentIndex.preload(:user, :post).records
PostIndex.includes(comments: :user).records
```

or `#eager_load`

```ruby
CommentIndex.eager_load(:user, :post).records
PostIndex.eager_load(comments: :user).records
```

or `#includes`

```ruby
CommentIndex.includes(:user, :post).records
PostIndex.includes(comments: :user).records
```

* `find_in_batches`

Used to fetch and yield records in batches using the ElasicSearch scroll API.
The batch size and scroll API timeout can be specified.

```ruby
CommentIndex.search("hello world").find_in_batches(batch_size: 100) do |batch|
  # ...
end
```

* `find_results_in_batches`

Used like `find_in_batches`, but yielding the raw results (as
`SearchFlip::Result` objects) instead of database records.

```ruby
CommentIndex.search("hello world").find_results_in_batches(batch_size: 100) do |batch|
  # ...
end
```

* `find_each`

Like `#find_in_batches` but yielding one record at a time.

```ruby
CommentIndex.search("hello world").find_each(batch_size: 100) do |record|
  # ...
end
```

* `find_each_result`

Like `#find_results_in_batches`, but yielding one record at a time.

```ruby
CommentIndex.search("hello world").find_each_result(batch_size: 100) do |batch|
  # ...
end
```

* `scroll`

You can as well use the underlying scroll API directly, ie. without using higher
level scrolling:

```ruby
query = CommentIndex.scroll(timeout: "5m")

until query.records.empty?
  # ...

  query = query.scroll(id: query.scroll_id, timeout: "5m")
end
```

* `failsafe`

Use `#failsafe` to prevent any exceptions from being raised for query string
syntax errors or ElasticSearch being unavailable, etc.

```ruby
CommentIndex.search("invalid/request").execute
# raises SearchFlip::ResponseError

# ...

CommentIndex.search("invalid/request").failsafe(true).execute
# => #<SearchFlip::Response ...>
```

* `merge`

You can merge criterias, ie. combine the attributes (constraints, settings,
etc) of two individual criterias:

```ruby
CommentIndex.where(approved: true).merge(CommentIndex.search("hello"))
# equivalent to: CommentIndex.where(approved: true).search("hello")
```

* `unscope`

You can even remove certain already added scopes via `#unscope`:

```ruby
CommentIndex.aggregate(:username).search("hello world").unscope(:search, :aggregate)
```

* `timeout`

Specify a timeout to limit query processing time:

```ruby
CommentIndex.timeout("3s").execute
```

* `terminate_after`

Activate early query termination to stop query processing after the specified
number of records has been found:

```ruby
CommentIndex.terminate_after(10).execute
```

For further details and a full list of methods, check out the reference docs.

* `custom`

You can add a custom clause to the request via `custom`

```ruby
CommentIndex.custom(custom_clause: '...')
```

This can be useful for Elasticsearch features not yet supported via criteria
methods by SearchFlip, custom plugin clauses, etc.

### Custom Criteria Methods

To add custom criteria methods, you can add class methods to your index class.

```ruby
class HotelIndex
  # ...

  def self.where_geo(lat:, lon:, distance:)
    filter(geo_distance: { distance: distance, location: { lat: lat, lon: lon } })
  end
end

HotelIndex.search("bed and breakfast").where_geo(lat: 53.57532, lon: 10.01534, distance: '50km').aggregate(:rating)
```

## Using multiple Elasticsearch clusters

To use multiple Elasticsearch clusters, specify a connection within your
indices:

```ruby
MyConnection = SearchFlip::Connection.new(base_url: "http://elasticsearch.host:9200")

class MyIndex
  include SearchFlip::Index

  def self.connection
    MyConnection
  end
end
```

This allows to use different clusters per index e.g. when migrating indices to
new versions of Elasticsearch.

## Routing and other index-time options

Override `index_options` in case you want to use routing or pass other
index-time options:

```ruby
class CommentIndex
  include SearchFlip::Index

  def self.index_options(comment)
    {
      routing: comment.user_id,
      version: comment.version,
      version_type: "external_gte"
    }
  end
end
```

These options will be passed whenever records get indexed, deleted, etc.

## Non-ActiveRecord models

SearchFlip ships with built-in support for ActiveRecord models, but using
non-ActiveRecord models is very easy. The model must implement a `find_each`
class method and the Index class needs to implement `Index.record_id` and
`Index.fetch_records`. The default implementations for the index class are as
follows:

```ruby
class MyIndex
  include SearchFlip::Index

  def self.record_id(object)
    object.id
  end

  def self.fetch_records(ids)
    model.where(id: ids)
  end
end
```

Thus, if your ORM supports `.find_each`, `#id` and `#where` you are already
good to go. Otherwise, simply add your custom implementation of those methods
that work with whatever ORM you use.

## Date and Timestamps in JSON

ElasticSearch requires dates and timestamps to have one of the formats listed
here: [https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-date-format.html#strict-date-time](https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-date-format.html#strict-date-time).

However, `JSON.generate` in ruby by default outputs something like:

```ruby
JSON.generate(time: Time.now.utc)
# => "{\"time\":\"2018-02-22 18:19:33 UTC\"}"
```

This format is not compatible with ElasticSearch by default. If you're on
Rails, ActiveSupport adds its own `#to_json` methods to `Time`, `Date`, etc.
However, ActiveSupport checks whether they are used in combination with
`JSON.generate` or not and adapt:

```ruby
Time.now.utc.to_json
=> "\"2018-02-22T18:18:22.088Z\""

JSON.generate(time: Time.now.utc)
=> "{\"time\":\"2018-02-22 18:18:59 UTC\"}"
```

SearchFlip is using the [Oj gem](https://github.com/ohler55/oj) to generate
JSON. More concretely, SearchFlip is using:

```ruby
Oj.dump({ key: "value" }, mode: :custom, use_to_json: true)
```

This mitigates the issues if you're on Rails:

```ruby
Oj.dump(Time.now, mode: :custom, use_to_json: true)
# => "\"2018-02-22T18:21:21.064Z\""
```

However, if you're not on Rails, you need to add `#to_json` methods to `Time`,
`Date` and `DateTime` to get proper serialization. You can either add them on
your own, via other libraries or by simply using:

```ruby
require "search_flip/to_json"
```

## Feature Support

* `#post_search` and `#profile` are only supported from up to ElasticSearch
  version >= 2.
* for ElasticSearch 2.x, the delete-by-query plugin is required to delete
  records via queries

## Keeping your Models and Indices in Sync

Besides the most basic approach to get you started, SarchFlip currently doesn't
ship with any means to automatically keep your models and indices in sync,
because every method is very much bound to the concrete environment and depends
on your concrete requirements. In addition, the methods to achieve model/index
consistency can get arbitrarily complex and we want to keep this bloat out of
the SearchFlip codebase.

```ruby
class Comment < ActiveRecord::Base
  include SearchFlip::Model

  notifies_index(CommentIndex)
end
```

It uses `after_commit` (if applicable, `after_save`, `after_destroy` and
`after_touch` otherwise) hooks to synchronously update the index when your
model changes.

## Links

* ElasticSearch: [https://www.elastic.co/](https://www.elastic.co/)
* Reference Docs: [http://www.rubydoc.info/github/mrkamel/search_flip](http://www.rubydoc.info/github/mrkamel/search_flip)
* Travis: [http://travis-ci.org/mrkamel/search_flip](http://travis-ci.org/mrkamel/search_flip)
* will_paginate: [https://github.com/mislav/will_paginate](https://github.com/mislav/will_paginate)
* kaminari: [https://github.com/kaminari/kaminari](https://github.com/kaminari/kaminari)
* Oj: [https://github.com/ohler55/oj](https://github.com/ohler55/oj)

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Running the test suite

Running the tests is super easy. The test suite uses sqlite, such that you only
need to install ElasticSearch. You can install ElasticSearch on your own, or
you can e.g. use docker-compose:

```
$ cd search_flip
$ sudo ES_IMAGE=elasticsearch:5.4 docker-compose up
$ rspec
```

That's it.
