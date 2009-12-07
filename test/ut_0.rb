class JigParticipantTests < Test::Unit::TestCase
  def setup
    require 'fakeweb' # gem install fakeweg
    require 'yajl'    # gem install yaijl-ruby
    require 'lib/ruote/jig/part/jig_participant'
    require 'rufus/jig/json'

    @engine = Engine.new
    @jig_participant = new_jig_participant()
    @test_hash = {'test' => {'foo' => 'bar', 'dash' => 'buzz'}}
    @test_hash_json = Rufus::Jig::Json.encode(@test_hash)
  end

  # test if the default options are treated ok
  def test_defaults
    FakeWeb.register_uri(:post, "http://127.0.0.1:3000/", :body => @test_hash_json, :content_type => 'application/json')
    @jig_participant.consume(wi = new_workitem) # ('params' => {'host' => 'localhost', 'port' => 3000, 'path' => '/'}))
    assert_equal(wi, @engine.workitem)
    assert_equal(@test_hash, @engine.workitem.fields['__jig_response__'])
    assert_equal(200, @engine.workitem.fields['__jig_status__'])
  end

  # test if the default options are overridden when others are passed at initialization time
  def test_initialization_options
    FakeWeb.register_uri(:get, 'http://foo:123/bar', :body => 'this is just a test', :content_type => 'text/plain')
    jp = new_jig_participant(:host => 'foo', :port => 123, :path => 'bar', :method => :get, :content_type => 'text/plain')
    jp.consume(new_workitem)
    assert_equal('this is just a test', @engine.workitem.fields['__jig_response__'])
  end

  # test if the options from the params field of the workitem are used above the defaults
  def test_params
    FakeWeb.register_uri(:post, 'http://127.100.100.100:80/baz', :body => @test_hash_json, :content_type => 'application/json')
    @jig_participant.consume(new_workitem('params' => {'host' => '127.100.100.100', 'port' => 80, 'path' => '/baz'}))
    assert_equal(@test_hash, @engine.workitem.fields['__jig_response__'])
  end

  def test_data_preparition
    jp = new_jig_participant(
      :content_type => 'text/plain',
      :data_preparition => Proc.new { |workitem| workitem.fields['my_data'] }
    )
    # overwrite Rufus::Jig::Http#do_post
    http = jp.instance_variable_get(:@http)
    def http.do_post(path, data, opts)
      r = {:status => 200, :body => data.reverse, :headers => {'Content-Type' => opts['Content-Type']}}
      def r.method_missing sym
        self[sym]
      end
      r
    end
    jp.consume(new_workitem('my_data' => '1234567890'))
    assert_equal('0987654321', @engine.workitem.fields['__jig_response__'])
  end

  def test_response_handling
    FakeWeb.register_uri(:post, "http://127.0.0.1:3000/", :body => '1234567890', :content_type => 'text/plain')
    jp = new_jig_participant(
      :content_type => 'text/plain',
      :response_handling => Proc.new {|response, workitem| workitem.set_field('my_result', response.reverse)}
    )
    jp.consume(new_workitem)
    assert_equal('0987654321', @engine.workitem.fields['my_result'])
  end

  protected

  class Engine
    attr_accessor :workitem
    def reply (wi)
      @workitem = wi
    end
  end

  def new_jig_participant(opts = {})
    jp = Ruote::Jig::JigParticipant.new opts
    jp.instance_variable_set(:@engine, @engine)
    def jp.engine
      @engine
    end
    jp
  end

  def new_workitem(fields = {})
    wi = {'params' => {}}.merge(fields)
    def wi.fields
      self
    end
    def wi.to_h
      self
    end
    def wi.set_field(k, v)
      self[k] = v
    end
    wi
  end
end
