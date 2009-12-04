require 'rubygems'

require 'ruote/engine'     # gem install ruote
require 'ruote/log/logger'

require 'patron' # gem install patron
require 'yajl'   # gem install yajl-ruby

require 'lib/ruote/jig/part/jig_participant'


e = Ruote::Engine.new

# e.register_listener Ruote::Logger.new, :name => :s_logger # uncomment to have some debug output

e.register_participant :jig, Ruote::Jig::JigParticipant
e.register_participant :put_fields do |wi|
  puts wi.fields.inspect
end

pdef = Ruote.process_definition :name => 'test' do
  sequence do
    jig :path => '/my/index', :method => :post
    put_fields
  end
end

wfid = e.launch(pdef)

e.wait_for(wfid)