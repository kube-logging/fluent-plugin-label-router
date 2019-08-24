#
# Copyright 2019- Banzai Cloud
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "fluent/plugin/output"
require 'digest/md5'

module Fluent
  module Plugin
    class LabelRouterOutput < BareOutput
      Fluent::Plugin.register_output("label_router", self)

      helpers :event_emitter, :record_accessor

      #record_accessor_create("log")
      #record_accessor_create("$.key1.key2")
      #record_accessor_create("$['key1'][0]['key2']")

      config_section :route, param_name: :routes, multi: true do
        desc "Label definition to match record. Example: app:nginx. You can specify more values as comma separated list: key1:value1,key2:value2"
        config_param :labels, :hash, :default => {}
        desc "Namespaces definition to filter the record. Ignored if left empty."
        config_param :namespace, :string, :default => ""
        desc "New @LABEL if selectors matched"
        config_param :@label, :string, :default => nil
        desc "New tag if selectors matched"
        config_param :tag, :string, :default => ""
      end

      class Route
        def initialize(selector, namespace, tag, router)
          @router = router
          @selector = selector
          @namespace = namespace
          @tag = tag
        end

        def match?(labels, namespace)
          # Match labels and namespace if defined
          return (match_labels(labels, @selector) and (@namespace ==  "" or namespace == @namespace))
        end

        def emit(tag, time, record)
          if @tag.empty?
            @router.emit(tag, time, record)
          else
            @router.emit(@tag, time, record)
          end
        end

        def emit_es(tag, es)
          if @tag.empty?
            @router.emit_stream(tag, es)
          else
            @router.emit_stream(@tag, es)
          end
        end
        def match_labels(input, match)
          return (match.to_a - input.to_a).empty?
        end
      end

      def process(tag, es)
        es.each do |time, record|
          input_labels = @access_to_labels.call(record).to_h
          input_namespace = @access_to_namespace.call(record).to_s
          @routers.each do |r|
            if r.match?(input_labels, input_namespace)
              r.emit(tag, time, record)
            end
          end
        end
      end

      def configure(conf)
        super
        @routers = []
        @routes.each do |rule|
          route_router = event_emitter_router(rule['@label'])
          @routers << Route.new(rule.labels, rule.namespace.to_s, rule.tag.to_s, route_router)
        end

        @access_to_labels = record_accessor_create("$.kubernetes.labels")
        @access_to_namespace = record_accessor_create("$.kubernetes.namespace_name")
      end
    end
  end
end