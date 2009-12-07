#--
# Copyright (c) 2009, Torsten Schönebaum (http://github.com/tosch/)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Made in Europe.
#++

require 'rufus/jig' # gem install rufus-jig

require 'ruote/engine/context'         # gem install ruote
require 'ruote/part/local_participant' # gem install ruote

module Ruote
  module Jig
    #
    # Ruote 2.0 participant which does a HTTP call using rufus-jig
    # (http://rufus.rubyforge.org/rufus-jig/), a HTTP client, greedy with JSON
    # content.
    #
    # By default, it POSTs received workitems as JSON to a HTTP server and
    # stores the answer back into the workitem. If the answer is in JSON, it is
    # automatically converted into Ruby data types (this magic is thanks to
    # rufus-jig).
    #
    # The handling of outgoing and incoming data may be customized by Procs.
    #
    # == Using it
    #   require 'yajl' # by default, you will need some JSON lib (yajl-ruby or json 'pure' or ActiveSupport)
    #
    #   # require this lib
    #   require 'ruote/jig/part/jig_participant'
    #
    #   # let's assume you have a ruote engine in '''engine'''
    #   engine.register_participant :jig_default, Ruote::Jig::JigParticipant
    #   engine.register_participant :jig_advanced, Ruote::Jig::JigParticipant.new(
    #     :host              => 'somehost',
    #     :port              => 80,
    #     :path              => '/path/to/the/magic',
    #     :method            => :post,
    #     :content_type      => 'foo/bar',
    #     :data_preparition  => Proc.new {|workitem| workitem.fields['foo_bar'].to_s},
    #     :response_handling => Proc.new do |response, workitem|
    #       workitem.set_field('incoming_foo_bar', FooBar.from_str(response.body))
    #     end
    #   )
    #
    #   # in a workflow definition...
    #   participant :ref => 'jig_default' # will POST the current workitem as JSON
    #                                     # to http://127.0.0.1:3000/ and save the
    #                                     # responded data in the workitem field
    #                                     # __jig_response__
    #
    #   participant :ref => 'jig_advanced', # will PUT the the string returned by
    #     :host   => 'anotherhost',         # workitem.fields['foo_bar'].to_s to
    #     :path   => '/path/to/bar',        # http://anotherhost:80/path/to/bar,
    #     :method => :put                   # processes the response body and
    #                                       # saves the result in the workitem
    #                                       # field 'incoming_foo_bar'
    #
    # == Getting help
    # * http://groups.google.com/group/openwferu-users
    # * irc.freenode.net #ruote
    #
    # == Issue tracker
    # http://github.com/tosch/ruote-jig/issues
    #
    class JigParticipant
      include Ruote::EngineContext
      include Ruote::LocalParticipant

      #
      # ==options hash
      # :host <String>:: The host to connect to (defaults to 127.0.0.1)
      # :port <Fixnum>:: ...and its port (defaults to 3000)
      # :path <String>:: The path part of the URL. Defaults to '/'.
      # :method <Symbol>:: Which HTTP method shall be used? One of :get, :post, :put and :delete.
      # :options_for_jig <Hash>:: Hash of options which will be passed to Rufus::Jig::Http.new.
      # :options_for_jig_requests <Hash>:: Hash of options which will be passed to the get, put, post or delete method of Rufus::Jig::Http
      # :response_handling <Proc>:: An optional Proc which handles the results Rufus::Jig::Http returns. Takes the results and the workitem as arguments. By default (when no Proc is given), the server's response is stored in the workitem field __jig_response__ and the HTTP status code in __jig_status__.
      # :data_preparition <Proc>:: An optional Proc which prepares the data being sent with POST or PUT requests. Takes the workitem as argument. Should return a string or another type Rufus::Jig::Http can handle. By default (if no Proc is given), the workitem will be converted into a Hash (and then into a JSON string by rufus-jig).
      # :content_type <String or Symbol>:: The content type to use for the HTTP request. Defaults to :json. Other types has to be submitted as strings. Note that you really should provide a :data_preparition-Proc if you don't use JSON!
      #
      # All options may be overridden by params when calling the participant in
      # a workflow definition.
      #
      def initialize(options = {})
        @options = options

        # some defaults
        @options[:host] ||= '127.0.0.1'
        @options[:port] ||= 3000
        @options[:method] ||= :post
        @options[:path] ||= '/'
        @options[:content_type] ||= :json

        @http = Rufus::Jig::Http.new @options[:host], @options[:port], @options[:options_for_jig] || {}
      end

      def consume workitem
        # do we need a new instance of the http client?
        http = if(@http.host == param(workitem, :host) and @http.port == param(workitem, :port))
          @http
        else
          Rufus::Jig::Http.new param(workitem, :host), param(workitem, :port), @options[:options_for_jig] || {}
        end

        # fire the request...
        response = case param(workitem, :method).to_sym
        when :get
          http.get param(workitem, :path), prepare_request_options(workitem)
        when :post
          http.post param(workitem, :path), prepare_data(workitem), prepare_request_options(workitem)
        when :put
          http.put param(workitem, :path), prepare_data(workitem), prepare_request_options(workitem)
        when :delete
          http.delete param(workitem, :path), prepare_request_options(workitem)
        else
          raise "Method #{param(workitem, :method).to_s} not supported"
        end

        # ... and handle the response
        if (block = param(workitem, :response_handling)).is_a?(Proc)
          # there is a proc which does the response handling for us
          block.call(response, workitem)
        else
          # we'll have to do the handling by ourselves
          case response
          when Rufus::Jig::HttpResponse
            workitem.set_field '__jig_response__', response.body
            workitem.set_field '__jig_status__', response.status
          else
            workitem.set_field '__jig_response__', response
            workitem.set_field '__jig_status__', http.last_response.status
          end
        end

        # reply the workitem to the engine
        reply_to_engine(workitem)
      end

      # For now, does nothing.
      # Could stop a running consume method some day?
      def cancel
      end

      protected

      #
      # extract parameter from params field of workitem or use default from
      # options hash
      #
      def param workitem, key
        workitem.fields['params'][key.to_s] || @options[key]
      end

      #
      # Prepare the data for post and put requests. Returns the workitem as
      # hash by default or the results of the executed Proc given in the options
      # as :data_preparition.
      #
      def prepare_data workitem
        if((block = param(workitem, :data_preparition)).is_a?(Proc))
          block.call workitem
        else
          workitem.to_h
        end
      end

      #
      # Prepare the request options to be submitted to rufus-jig.
      #
      def prepare_request_options workitem
        {
          :content_type => param(workitem, :content_type),
          :params => param(workitem, :params) || nil
        }.merge(param(workitem, :options_for_jig_request) || {})
      end
    end
  end
end