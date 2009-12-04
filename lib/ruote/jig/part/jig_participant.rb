require 'rufus/jig' # gem install rufus-jig

require 'ruote/engine/context'         # gem install ruote
require 'ruote/part/local_participant' # gem install ruote

module Ruote
  module Jig
    class JigParticipant
      include Ruote::EngineContext
      include Ruote::LocalParticipant

      #
      # ==options hash
      # :host::
      # :port::
      # :path::
      # :method::
      # :options_for_jig::
      # :options_for_jig_requests::
      # :response_handling::
      # :data_preparition::
      #
      def initialize(options = {})
        @options = options

        # some defaults
        @options[:host] ||= '127.0.0.1'
        @options[:port] ||= 3000
        @options[:method] ||= :get
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
      
      def param workitem, key
        workitem.fields['params'][key.to_s] || @options[key]
      end

      def prepare_data workitem
        if(block = param(workitem, :data_preparition).is_a?(Proc))
          block.call workitem
        else
          workitem.to_h
        end
      end

      def prepare_request_options workitem
        {
          :content_type => param(workitem, :content_type),
          :params => param(workitem, :params) || nil
        }
      end
    end
  end
end